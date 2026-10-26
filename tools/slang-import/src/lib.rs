//! Offline, bounded RGBA8 slang -> LÖVE importer. No compiler is loaded by the game.
use librashader_common::{FilterMode, ImageFormat, WrapMode};
use librashader_preprocess::ShaderSource;
use librashader_presets::{ScaleFactor, ScaleType, Scaling, ShaderFeatures, ShaderPreset};
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
    io::{Read, Write},
    path::{Path, PathBuf},
    process::Command,
};
pub type Result<T> = std::result::Result<T, Box<dyn Error>>;

pub struct ConvertedPass {
    pub metadata: Value,
    pub sources: [String; 4],
}
pub struct ConvertedTexture {
    pub metadata: Value,
    pub bytes: Vec<u8>,
}
pub struct Converted {
    pub metadata: Value,
    pub passes: Vec<ConvertedPass>,
    pub textures: Vec<ConvertedTexture>,
}
fn binding(
    semantic: TextureSemantics,
    index: usize,
    pass: usize,
    textures: usize,
    legacy: bool,
) -> Result<String> {
    Ok(match (semantic, index) {
        (TextureSemantics::Source, 0) => "g2_Source".into(),
        (TextureSemantics::Original, 0) => if legacy { "g2_Source" } else { "g2_Original" }.into(),
        (TextureSemantics::PassOutput, n) if n < pass => format!("g2_Pass{n}"),
        (TextureSemantics::User, n) if n < textures => format!("g2_Lut{n}"),
        _ => {
            return Err(
                "history, feedback, future or unknown texture binding is unsupported".into(),
            );
        }
    })
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
    pass: usize,
    textures: usize,
    legacy: bool,
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
                if *ty != "vec4" {
                    return Err("texture size must be vec4".into());
                }
                let name = binding(v.semantics, v.index, pass, textures, false)?;
                format!("{name}Size")
            } else {
                return Err(format!("unknown uniform: {name}").into());
            };
            if binding != "transform_projection" {
                declarations.push_str(&format!("uniform highp {ty} {binding};\n"));
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
        let target = binding(semantic.semantics, semantic.index, pass, textures, legacy)?;
        s = replace_word(&s, name, &target);
    }
    s = samplers.replace_all(&s, "").into_owned();
    let mut bindings: Vec<String> = vec!["g2_Source".into(), "g2_Original".into()];
    bindings.extend((0..pass).map(|i| format!("g2_Pass{i}")));
    bindings.extend((0..textures).map(|i| format!("g2_Lut{i}")));
    for name in bindings {
        if rx(&format!(r"\b{name}\b")).is_match(&s) {
            declarations.push_str(&format!("uniform highp Image {name};\n"));
        }
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
    if p.passes.is_empty() || p.passes.len() > 8 || p.pass_count as usize != p.passes.len() {
        return Err("one to eight shader passes are supported".into());
    }
    if p.textures.len() > 8 {
        return Err("at most eight LUT textures are supported".into());
    }
    let legacy = p.passes.len()==1 && p.textures.is_empty() && (!p.passes[0].meta.scaling.valid || [&p.passes[0].meta.scaling.x,&p.passes[0].meta.scaling.y].iter().all(|s| matches!((&s.scale_type,&s.factor),(ScaleType::Viewport,ScaleFactor::Float(f)) if *f==1.0)));
    let mut loaded = Vec::new();
    let mut parameters: Vec<Value> = Vec::new();
    for pass in &p.passes {
        if pass.meta.srgb_framebuffer || pass.meta.float_framebuffer || pass.meta.mipmap_input {
            return Err("special framebuffer/mipmap formats are not supported".into());
        }
        let source = ShaderSource::load(&pass.path, p.features)?;
        if !matches!(
            source.format,
            ImageFormat::Unknown | ImageFormat::R8G8B8A8Unorm
        ) {
            return Err("shader requires an unsupported output format".into());
        }
        for v in source.parameters.values() {
            let param = json!({"id":v.id.to_string(),"name":v.description,"default":v.initial,"min":v.minimum,"max":v.maximum,"step":v.step});
            if let Some(old) = parameters.iter().find(|old| old["id"] == param["id"]) {
                if *old != param {
                    return Err("conflicting parameter definitions across passes".into());
                }
            } else {
                parameters.push(param);
            }
        }
        loaded.push(source);
    }
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
    let mut passes = Vec::new();
    for (i, pass) in p.passes.iter().enumerate() {
        let semantics = ShaderSemantics::create_pass_semantics::<Box<dyn Error>>(&p, i)?;
        let mut sources = Vec::new();
        for version in [GlslVersion::Glsl120, GlslVersion::Glsl100Es] {
            let compiled = Glslang::compile(&loaded[i])?;
            let mut target = GLSL::from_compilation(compiled)?;
            target.reflect(i, &semantics)?;
            let out = target.compile(version)?;
            sources.push(adapt(
                &out.fragment,
                false,
                &semantics,
                &parameters,
                i,
                p.textures.len(),
                legacy,
            )?);
            sources.push(adapt(
                &out.vertex,
                true,
                &semantics,
                &parameters,
                i,
                p.textures.len(),
                legacy,
            )?);
        }
        if sources.iter().any(|s| s.len() > 65536) {
            return Err("converted shader exceeds 64 KiB".into());
        }
        let (x, y) = if pass.meta.scaling.valid {
            (
                scaling(&pass.meta.scaling.x)?,
                scaling(&pass.meta.scaling.y)?,
            )
        } else {
            let kind = if i + 1 == p.passes.len() {
                "viewport"
            } else {
                "source"
            };
            (
                json!({"type":kind,"value":1}),
                json!({"type":kind,"value":1}),
            )
        };
        passes.push(ConvertedPass {metadata:json!({"filter":filter(pass.meta.filter),"wrap":wrap(pass.meta.wrap_mode),"scaleX":x,"scaleY":y}),sources:sources.try_into().unwrap()});
    }
    let mut textures = Vec::new();
    let mut pixels = 0u64;
    for t in &p.textures {
        if t.meta.mipmap || !identifier(t.meta.name.as_str()) {
            return Err("unsupported LUT identifier/mipmap".into());
        }
        // Bound compressed data and decoded allocation before invoking the image decoder.
        if fs::metadata(&t.path)?.len() > 8 * 1024 * 1024 {
            return Err("LUT file too large".into());
        }
        let mut bytes = Vec::new();
        fs::File::open(&t.path)?
            .take(8 * 1024 * 1024 + 1)
            .read_to_end(&mut bytes)?;
        pixels += png_pixels(&bytes)?;
        if pixels > 8 * 1024 * 1024 {
            return Err("LUT pixel budget exceeded".into());
        }
        textures.push(ConvertedTexture { metadata:json!({"id":t.meta.name.as_str(),"filter":filter(t.meta.filter_mode),"wrap":wrap(t.meta.wrap_mode)}),bytes});
    }
    let mut metadata = json!({"format":if legacy {2}else{3},"name":name,"parameters":parameters});
    if legacy {
        for key in ["filter", "wrap"] {
            metadata[key] = passes[0].metadata[key].clone();
        }
    }
    Ok(Converted {
        metadata,
        passes,
        textures,
    })
}
fn filter(v: FilterMode) -> &'static str {
    match v {
        FilterMode::Linear => "linear",
        FilterMode::Nearest => "nearest",
    }
}
fn wrap(v: WrapMode) -> &'static str {
    match v {
        WrapMode::ClampToBorder => "clampzero",
        WrapMode::ClampToEdge => "clamp",
        WrapMode::Repeat => "repeat",
        WrapMode::MirroredRepeat => "mirroredrepeat",
    }
}
fn scaling(s: &Scaling) -> Result<Value> {
    let value: f32 = s.factor.into();
    let kind = match s.scale_type {
        ScaleType::Input => "source",
        ScaleType::Original => "original",
        ScaleType::Viewport => "viewport",
        ScaleType::Absolute => "absolute",
    };
    if !value.is_finite()
        || (kind == "absolute" && (value < 1.0 || value > 8192.0 || value.fract() != 0.0))
        || (kind != "absolute" && !(1.0 / 64.0..=8.0).contains(&value))
    {
        return Err("unsupported scaling range".into());
    }
    Ok(json!({"type":kind,"value":value}))
}
fn png_pixels(bytes: &[u8]) -> Result<u64> {
    if bytes.len() < 33
        || bytes.len() > 8 * 1024 * 1024
        || &bytes[..16] != b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR"
    {
        return Err("LUT must be a bounded PNG".into());
    }
    let w = u32::from_be_bytes(bytes[16..20].try_into()?);
    let h = u32::from_be_bytes(bytes[20..24].try_into()?);
    if !(1..=2048).contains(&w)
        || !(1..=2048).contains(&h)
        || bytes[24] != 8
        || ![0, 2, 3, 4, 6].contains(&bytes[25])
    {
        return Err("unsupported LUT dimensions/bit depth".into());
    }
    Ok(w as u64 * h as u64)
}

/// Descriptor and all referenced resources, with a deterministic closed basename namespace.
type Bundle = (Value, Vec<(String, Vec<u8>)>);
pub(crate) fn bundle(c: &Converted, stem: &str, force_graph: bool) -> Result<Bundle> {
    let mut meta = c.metadata.clone();
    let mut files = Vec::new();
    let mut passes = Vec::new();
    let mut textures = Vec::new();
    for (i, p) in c.passes.iter().enumerate() {
        let mut pass = p.metadata.clone();
        for ((key, suffix), source) in ["shader", "vertex", "esShader", "esVertex"]
            .iter()
            .zip(["f", "v", "ef", "ev"])
            .zip(&p.sources)
        {
            let name = if c.metadata["format"] == 2 && !force_graph {
                format!("{stem}-{suffix}.glsl")
            } else {
                format!("{stem}-p{i}-{suffix}.glsl")
            };
            pass[*key] = json!(name);
            files.push((name, source.as_bytes().to_vec()));
        }
        passes.push(pass);
    }
    for (i, t) in c.textures.iter().enumerate() {
        let mut tex = t.metadata.clone();
        let name = format!("{stem}-t{i}.png");
        tex["image"] = json!(name);
        files.push((name, t.bytes.clone()));
        textures.push(tex);
    }
    if force_graph || c.metadata["format"] == 3 {
        meta["format"] = json!(3);
        meta["passes"] = json!(passes);
        meta["textures"] = json!(textures);
    } else {
        for key in ["shader", "vertex", "esShader", "esVertex"] {
            meta[key] = passes[0][key].clone();
        }
    }
    Ok((meta, files))
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
        fs::write(
            dir.join("ShaderGraph.lua"),
            include_str!("../../../src/render/ShaderGraph.lua"),
        )?;
        fs::write(
            dir.join("Json.lua"),
            include_str!("../../../src/link/Json.lua"),
        )?;
        let (meta, files) = bundle(converted, "probe", true)?;
        for (name, bytes) in files {
            fs::write(dir.join(name), bytes)?;
        }
        fs::write(dir.join("graph.json"), serde_json::to_vec(&meta)?)?;
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
    publish_checked(converted, destination, || Ok(()))
}
type Publication = (String, Vec<(String, Vec<u8>)>);
fn publication(converted: &Converted) -> Result<Publication> {
    let mut hash = Sha256::new();
    hash.update(converted.metadata.to_string());
    for p in &converted.passes {
        hash.update(p.metadata.to_string());
        for source in &p.sources {
            hash.update((source.len() as u64).to_le_bytes());
            hash.update(source);
        }
    }
    for t in &converted.textures {
        hash.update(t.metadata.to_string());
        hash.update((t.bytes.len() as u64).to_le_bytes());
        hash.update(&t.bytes);
    }
    let stem = format!("slang-{:x}", hash.finalize());
    let stem = &stem[..38];
    let (meta, mut files) = bundle(converted, stem, false)?;
    let descriptor = serde_json::to_vec_pretty(&meta)?;
    if descriptor.len() > 16384 {
        return Err("descriptor exceeds 16 KiB".into());
    }
    files.push((format!("{stem}.json"), descriptor));
    Ok((stem.to_string(), files))
}
pub(crate) fn existing(converted: &Converted, destination: &Path) -> Option<PathBuf> {
    let (stem, files) = publication(converted).ok()?;
    for (name, bytes) in files {
        let f = fs::File::open(destination.join(name)).ok()?;
        let mut read = Vec::new();
        f.take(bytes.len() as u64 + 1).read_to_end(&mut read).ok()?;
        if bytes != read {
            return None;
        }
    }
    Some(destination.join(format!("{stem}.json")))
}
pub(crate) fn publish_checked<F: FnMut() -> Result<()>>(
    converted: &Converted,
    destination: &Path,
    mut check: F,
) -> Result<PathBuf> {
    check()?;
    let (stem, files) = publication(converted)?;
    fs::create_dir_all(destination)?;
    let path = destination.join(format!("{stem}.json"));
    let mut created = Vec::new();
    let result = (|| -> Result<PathBuf> {
        for (name, contents) in &files {
            check()?;
            let p = destination.join(name);
            let mut f = OpenOptions::new().write(true).create_new(true).open(&p)?;
            created.push(p);
            f.write_all(contents)?;
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

pub mod browser;
