//! Offline, single-pass slang -> LÖVE importer. No compiler is loaded by the game.
use librashader_common::{FilterMode, ImageFormat, WrapMode};
use librashader_preprocess::ShaderSource;
use librashader_presets::{ScaleFactor, ScaleType, ShaderFeatures, ShaderPreset};
use librashader_reflect::{
    back::{CompileShader, FromCompilation, glsl::GlslVersion, targets::GLSL},
    front::{Glslang, ShaderInputCompiler},
    reflect::{
        ReflectShader,
        semantics::{
            ShaderSemantics, TextureSemanticMap, TextureSemantics, UniqueSemanticMap,
            UniqueSemantics,
        },
    },
};
use regex::Regex;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    error::Error,
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    process::Command,
};
pub type Result<T> = std::result::Result<T, Box<dyn Error>>;

pub struct Converted {
    pub metadata: Value,
    pub sources: [String; 4], // desktop fragment/vertex, GLES fragment/vertex
}
fn rx(pattern: &str) -> Regex {
    Regex::new(pattern).expect("internal regex")
}
fn replace_word(source: &str, word: &str, replacement: &str) -> String {
    rx(&format!(r"\b{}\b", regex::escape(word)))
        .replace_all(source, replacement)
        .into_owned()
}
fn printable(s: &str) -> bool {
    !s.is_empty() && s.len() <= 48 && s.bytes().all(|b| (32..=126).contains(&b))
}
fn identifier(s: &str) -> bool {
    s.len() <= 32
        && rx(r"^[A-Za-z_][A-Za-z0-9_]*$").is_match(s)
        && !s.starts_with("love_")
        && !s.starts_with("g2_")
        && s != "sourceSize"
        && s != "pixelScale"
}

/// Adapt compiler-generated GLSL, never the original Vulkan shader text.
fn adapt(
    input: &str,
    vertex: bool,
    semantics: &ShaderSemantics,
    params: &[Value],
) -> Result<String> {
    if input.contains("g2_") {
        return Err("reserved g2_ identifier in shader".into());
    }
    let mut s =
        rx(r"(?m)^#version[^\n]*\n|^#extension GL_EXT_gpu_shader4[^\n]*\n|^precision [^\n]*\n")
            .replace_all(input, "")
            .into_owned();
    let blocks = rx(
        r"(?s)struct (LIBRA_(?:PUSH|UBO)_(?:VERTEX|FRAGMENT))\s*\{([^}]+)\};\s*uniform\s+\w+\s+(\w+);\s*",
    );
    let mut declarations = String::new();
    for cap in blocks.captures_iter(&s.clone()) {
        let instance = &cap[3];
        for field in cap[2].split(';').map(str::trim).filter(|v| !v.is_empty()) {
            let parts: Vec<_> = field.split_whitespace().collect();
            let [ty, name] = parts.as_slice() else {
                // The ES backend can add precision to integer members.
                if parts.len() != 3 || !["lowp", "mediump", "highp"].contains(&parts[0]) {
                    return Err(format!("unsupported uniform field: {field}").into());
                }
                continue;
            };
            let qualified = format!("{instance}.{name}");
            if !rx(&format!(r"\b{}\b", regex::escape(&qualified))).is_match(&s) {
                continue;
            } // unused block members have no runtime requirements
            let binding = if let Some(p) = params.iter().find(|p| p["id"] == *name) {
                if *ty != "float" {
                    return Err("parameters must be scalar floats".into());
                }
                format!("g2_p_{}", p["id"].as_str().unwrap())
            } else if let Some(v) = semantics.uniform_semantics.unique_semantic(name) {
                match v.semantics {
                    UniqueSemantics::MVP if vertex && *ty == "mat4" => {
                        "transform_projection".into()
                    }
                    UniqueSemantics::Output if *ty == "vec4" => "g2_OutputSize".into(),
                    UniqueSemantics::FinalViewport if *ty == "vec4" => {
                        "g2_FinalViewportSize".into()
                    }
                    // Unsigned arithmetic is deliberately outside GLSL 1.20/ES 1.00 import.
                    _ => return Err(format!("unsupported uniform: {name}").into()),
                }
            } else if let Some(v) = semantics.uniform_semantics.texture_semantic(name) {
                match (v.semantics, v.index, *ty) {
                    (TextureSemantics::Source, 0, "vec4") => "g2_SourceSize".into(),
                    (TextureSemantics::Original, 0, "vec4") => "g2_OriginalSize".into(),
                    _ => return Err(format!("unsupported texture-size uniform: {name}").into()),
                }
            } else {
                return Err(format!("unknown uniform: {name}").into());
            };
            if binding != "transform_projection" {
                declarations.push_str(&format!("uniform {ty} {binding};\n"));
            }
            s = replace_word(&s, &qualified, &binding);
        }
        // Precision-qualified members are supported only when unused, never silently omitted.
        if let Some(member) = rx(&format!(
            r"\b{}\.([A-Za-z_][A-Za-z0-9_]*)",
            regex::escape(instance)
        ))
        .captures_iter(&s)
        .next()
        {
            return Err(format!("unsupported uniform: {}", &member[1]).into());
        }
    }
    s = blocks.replace_all(&s, "").into_owned();
    let samplers = rx(r"uniform\s+(?:(?:highp|mediump|lowp)\s+)?sampler2D\s+(\w+);\s*");
    for cap in samplers.captures_iter(&s.clone()) {
        let name = &cap[1];
        let logical = name
            .strip_prefix("LIBRA_TEXTURE_")
            .ok_or("unknown sampler")?;
        let semantic = semantics
            .texture_semantics
            .texture_semantic(logical)
            .ok_or("unknown sampler semantic")?;
        if !matches!(
            (semantic.semantics, semantic.index),
            (TextureSemantics::Source | TextureSemantics::Original, 0)
        ) {
            return Err(format!("unsupported sampler: {logical}").into());
        }
        s = replace_word(&s, name, "g2_Source");
    }
    // Repeated Source/Original aliases refer to the same input in a single pass.
    s = samplers.replace_all(&s, "").into_owned();
    if s.contains("g2_Source") {
        declarations.push_str("uniform Image g2_Source;\n");
    }
    if vertex {
        s = rx(r"attribute vec4 Position;\s*|attribute vec2 TexCoord;\s*")
            .replace_all(&s, "")
            .into_owned();
        s = replace_word(&s, "Position", "vertex_position");
        s = replace_word(&s, "TexCoord", "VertexTexCoord.xy");
        s = replace_word(&s, "gl_Position", "g2_result");
    } else {
        s = s.replace("gl_FragData[0]", "g2_result");
    }
    // This bounded adapter accepts the one main() emitted last by SPIRV-Cross.
    let main = rx(r"void main\(\)\s*\{");
    if main.find_iter(&s).count() != 1 || !s.trim_end().ends_with('}') {
        return Err("unsupported entry point".into());
    }
    let header = if vertex {
        "vec4 position(mat4 transform_projection, vec4 vertex_position) { vec4 g2_result = vec4(0.0);"
    } else {
        "vec4 effect(vec4 g2_unusedColor, Image g2_unusedImage, vec2 g2_unusedUv, vec2 g2_unusedPixel) { vec4 g2_result = vec4(0.0);"
    };
    s = main.replace(&s, header).into_owned();
    s = rx(r"\breturn\s*;")
        .replace_all(&s, "return g2_result;")
        .into_owned();
    let end = s.rfind('}').ok_or("missing main body")?;
    s.insert_str(end, "return g2_result;\n");
    // Catch extension-dependent operations and unrecognized interfaces rather than change their meaning.
    if rx(r"\b(uint|uvec[234]|gl_FragData|gl_FragColor|attribute|LIBRA_(?:PUSH|UBO|TEXTURE)_\w*)\b|(?m)^#extension").is_match(&s) {
        return Err("shader needs an unsupported GLSL interface or extension".into());
    }
    // LÖVE supplies stage-specific precision; retain the same varying precision in both stages.
    Ok(format!("{declarations}\n{s}"))
}

pub fn convert(path: &Path, name: &str) -> Result<Converted> {
    if !printable(name) {
        return Err("name must contain 1-48 printable ASCII characters".into());
    }
    if path.extension().and_then(|e| e.to_str()) != Some("slangp") {
        return Err("expected a .slangp preset".into());
    }
    let p = ShaderPreset::try_parse(path, ShaderFeatures::empty())?;
    if p.pass_count != 1 || p.passes.len() != 1 {
        return Err("only single-pass presets are supported".into());
    }
    if !p.textures.is_empty() {
        return Err("LUT textures are not supported".into());
    }
    let pass = &p.passes[0];
    if pass.meta.srgb_framebuffer || pass.meta.float_framebuffer || pass.meta.mipmap_input {
        return Err("special framebuffer/mipmap formats are not supported".into());
    }
    if pass.meta.scaling.valid && [&pass.meta.scaling.x, &pass.meta.scaling.y].iter().any(|s| !matches!((&s.scale_type, &s.factor), (ScaleType::Viewport, ScaleFactor::Float(f)) if *f == 1.0)) {
        return Err("only default or viewport 1x output scaling is supported".into());
    }
    let source = ShaderSource::load(&pass.path, p.features)?;
    if !matches!(
        source.format,
        ImageFormat::Unknown | ImageFormat::R8G8B8A8Unorm
    ) {
        return Err("shader requires an unsupported output format".into());
    }
    let mut parameters: Vec<Value> = source.parameters.values().map(|v| json!({"id":v.id.to_string(),"name":v.description,"default":v.initial,"min":v.minimum,"max":v.maximum,"step":v.step})).collect();
    parameters.sort_by_key(|v| v["id"].as_str().unwrap_or_default().to_string());
    if parameters.len() > 8 {
        return Err("at most eight parameters are supported".into());
    }
    for param in &mut parameters {
        if let Some(v) = p
            .parameters
            .iter()
            .rev() // referenced presets come first; later overrides take precedence
            .find(|v| v.name.as_str() == param["id"].as_str().unwrap())
        {
            param["default"] = json!(v.value);
        }
        let id = param["id"].as_str().unwrap();
        if !identifier(id) || !printable(param["name"].as_str().unwrap_or("")) {
            return Err("invalid parameter identifier or label".into());
        }
        let nums: Vec<_> = ["min", "max", "step", "default"]
            .iter()
            .map(|k| param[*k].as_f64().unwrap_or(f64::NAN))
            .collect();
        let (lo, hi, step, def) = (nums[0], nums[1], nums[2], nums[3]);
        if nums.iter().any(|v| !v.is_finite())
            || lo >= hi
            || step <= 0.0
            || step > hi - lo
            || (hi - lo) / step > 1_000_000.0
            || def < lo
            || def > hi
        {
            return Err("invalid parameter range/default".into());
        }
    }
    let semantics = ShaderSemantics::create_pass_semantics::<Box<dyn Error>>(&p, 0)?;
    let mut sources: Vec<String> = Vec::new();
    for version in [GlslVersion::Glsl120, GlslVersion::Glsl100Es] {
        let compiled = Glslang::compile(&source)?;
        let mut target = GLSL::from_compilation(compiled)?;
        target.reflect(0, &semantics)?;
        let out = target.compile(version)?;
        sources.push(adapt(&out.fragment, false, &semantics, &parameters)?);
        sources.push(adapt(&out.vertex, true, &semantics, &parameters)?);
    }
    if sources.iter().any(|s| s.len() > 65536) {
        return Err("converted shader exceeds 64 KiB".into());
    }
    let wrap = match pass.meta.wrap_mode {
        WrapMode::ClampToBorder => "clampzero",
        WrapMode::ClampToEdge => "clamp",
        WrapMode::Repeat => "repeat",
        WrapMode::MirroredRepeat => "mirroredrepeat",
    };
    Ok(Converted {
        metadata: json!({"format":2,"name":name,"parameters":parameters,"filter": match pass.meta.filter { FilterMode::Linear => "linear", FilterMode::Nearest => "nearest" },"wrap":wrap}),
        sources: sources.try_into().unwrap(),
    })
}

/// Validate both dialects and compile the current GPU's pair BEFORE publication.
/// Runs LÖVE directly with argument boundaries, never through a shell.
pub fn preflight(converted: &Converted, love: &Path) -> Result<()> {
    let dir = std::env::temp_dir().join(format!(
        "gen2-slang-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_nanos()
    ));
    fs::create_dir(&dir)?;
    let result = (|| -> Result<()> {
        fs::write(
            dir.join("conf.lua"),
            "function love.conf(t) t.identity='gen2-slang-preflight'; t.window.visible=false; t.window.width=32; t.window.height=32; t.modules.audio=false; t.modules.joystick=false end",
        )?;
        fs::write(dir.join("main.lua"), include_str!("validate.lua"))?;
        for (i, source) in converted.sources.iter().enumerate() {
            fs::write(dir.join(format!("{i}.glsl")), source)?;
        }
        fs::write(
            dir.join("settings.txt"),
            format!(
                "{} {}",
                converted.metadata["filter"].as_str().unwrap(),
                converted.metadata["wrap"].as_str().unwrap()
            ),
        )?;
        // JSON parameters never become executable Lua.
        fs::write(
            dir.join("params.txt"),
            converted.metadata["parameters"]
                .as_array()
                .unwrap()
                .iter()
                .map(|p| format!("g2_p_{} {}\n", p["id"].as_str().unwrap(), p["default"]))
                .collect::<String>(),
        )?;
        let output = Command::new(love).arg(&dir).output()?;
        if !output.status.success() {
            return Err(format!(
                "LÖVE preflight failed:\n{}{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            )
            .into());
        }
        Ok(())
    })();
    let _ = fs::remove_dir_all(&dir);
    result
}

/// Content-addressed, create-new-only files, descriptor published last.
/// An interrupted import cannot expose a descriptor with partial source files.
pub fn publish(converted: &Converted, destination: &Path) -> Result<PathBuf> {
    let mut hash = Sha256::new();
    hash.update(converted.metadata.to_string());
    for s in &converted.sources {
        hash.update((s.len() as u64).to_le_bytes());
        hash.update(s);
    }
    let stem = format!("slang-{:x}", hash.finalize());
    let stem = &stem[..38];
    let names: Vec<_> = ["-f.glsl", "-v.glsl", "-ef.glsl", "-ev.glsl"]
        .iter()
        .map(|s| format!("{stem}{s}"))
        .collect();
    let mut meta = converted.metadata.clone();
    for (key, name) in ["shader", "vertex", "esShader", "esVertex"]
        .iter()
        .zip(&names)
    {
        meta[*key] = json!(name);
    }
    let descriptor = serde_json::to_string_pretty(&meta)?;
    if descriptor.len() > 16384 {
        return Err("descriptor exceeds 16 KiB".into());
    }
    fs::create_dir_all(destination)?;
    let path = destination.join(format!("{stem}.json"));
    let mut created = Vec::new();
    let result = (|| -> Result<PathBuf> {
        for (name, contents) in names
            .iter()
            .zip(&converted.sources)
            .chain(std::iter::once((&format!("{stem}.json"), &descriptor)))
        {
            let p = destination.join(name);
            let mut f = OpenOptions::new().write(true).create_new(true).open(&p)?;
            created.push(p);
            f.write_all(contents.as_bytes())?;
            f.sync_all()?;
        }
        Ok(path)
    })();
    if result.is_err() {
        for p in created {
            let _ = fs::remove_file(p);
        }
    }
    result
}
