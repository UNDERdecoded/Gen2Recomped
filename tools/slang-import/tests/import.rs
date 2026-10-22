use gen2_slang_import::{convert, publish};
use std::{
    fs,
    path::{Path, PathBuf},
};
fn fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("fixtures")
        .join(name)
}
struct Scratch(PathBuf);
impl Scratch {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "gen2-import-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir(&p).unwrap();
        Self(p)
    }
    fn preset(&self, text: &str) -> PathBuf {
        let p = self.0.join("test.slangp");
        let shader = fixture("probe.slang")
            .display()
            .to_string()
            .replace('\\', "/");
        fs::write(
            &p,
            format!(
                "{}shader0=\"{shader}\"\n{text}\n",
                if text.contains("shaders=") {
                    ""
                } else {
                    "shaders=1\n"
                }
            ),
        )
        .unwrap();
        p
    }
}
impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
#[test]
fn compiles_both_stages_and_dialects_with_includes_and_overrides() {
    let c = convert(&fixture("probe.slangp"), "PROBE").unwrap();
    assert_eq!(c.metadata["parameters"][0]["default"], 0.5);
    assert_eq!(c.metadata["parameters"][1]["id"], "unused");
    assert_eq!(c.metadata["filter"], "nearest");
    assert_eq!(c.metadata["wrap"], "clamp");
    for pair in c.sources.as_chunks::<2>().0 {
        assert!(pair[0].contains("vec4 effect("));
        assert!(pair[1].contains("vec4 position("));
        assert!(pair[0].contains("g2_p_gain"));
        assert!(pair[1].contains("g2_SourceSize"));
        assert!(!pair[0].contains("LIBRA_TEXTURE_"));
        assert!(!pair[1].contains("LIBRA_UBO_"));
    }
}
#[test]
fn referenced_presets_resolve_relative_sources_and_override_parameters() {
    let c = convert(&fixture("reference.slangp"), "REFERENCE").unwrap();
    assert!((c.metadata["parameters"][0]["default"].as_f64().unwrap() - 0.7).abs() < 0.00001);
}
#[test]
fn rejects_unsupported_pass_graph_formats_scaling_and_bad_metadata() {
    let t = Scratch::new();
    fs::write(t.0.join("probe.png"), "").unwrap();
    for (extra, error) in [
        ("shaders=2", "single-pass"),
        ("textures=lut\nlut=probe.png", "LUT"),
        ("float_framebuffer0=true", "framebuffer"),
        ("srgb_framebuffer0=true", "framebuffer"),
        ("mipmap_input0=true", "mipmap"),
        ("scale_type0=source\nscale0=2.0", "scaling"),
        ("scale_type0=absolute\nscale0=64", "scaling"),
        ("parameters=gain\ngain=2.0", "parameter range"),
    ] {
        assert!(
            convert(&t.preset(extra), "TEST")
                .err()
                .unwrap()
                .to_string()
                .contains(error),
            "{extra}"
        );
    }
    assert!(convert(&fixture("probe.slangp"), "\nINVALID").is_err());
    assert!(convert(&fixture("probe.slang"), "TEST").is_err());
    assert!(convert(&t.0.join("missing.slangp"), "TEST").is_err());
}
#[test]
fn rejects_history_feedback_time_and_source_format_requirements() {
    let t = Scratch::new();
    let original = fs::read_to_string(fixture("probe.slang")).unwrap().replace(
        "#include \"probe.inc\"",
        "float probeGain(float r,float g){return r*g;}",
    );
    for text in [
        original
            .replace("sampler2D Original", "sampler2D OriginalHistory1")
            .replace("texture(Original,", "texture(OriginalHistory1,"),
        original
            .replace("sampler2D Original", "sampler2D PassFeedback0")
            .replace("texture(Original,", "texture(PassFeedback0,"),
        original
            .replace("float unused;", "float unused; uint FrameCount;")
            .replace("params.gain)", "float(params.FrameCount))"),
        original.replace(
            "#version 450",
            "#version 450\n#pragma format R16G16B16A16_SFLOAT",
        ),
    ] {
        fs::write(t.0.join("bad.slang"), text).unwrap();
        fs::write(t.0.join("bad.slangp"), "shaders=1\nshader0=bad.slang").unwrap();
        assert!(convert(&t.0.join("bad.slangp"), "BAD").is_err());
    }
}
#[test]
fn publication_never_overwrites_and_rolls_back_only_its_own_files() {
    let t = Scratch::new();
    let c = convert(&fixture("probe.slangp"), "TEST").unwrap();
    let path = publish(&c, &t.0).unwrap();
    let snapshot = fs::read(&path).unwrap();
    assert_eq!(fs::read_dir(&t.0).unwrap().count(), 5);
    assert!(publish(&c, &t.0).is_err());
    assert_eq!(fs::read(&path).unwrap(), snapshot);
    let json: serde_json::Value = serde_json::from_slice(&snapshot).unwrap();
    for key in ["shader", "vertex", "esShader", "esVertex"] {
        let file = json[key].as_str().unwrap();
        assert!(file.len() <= 64 && t.0.join(file).is_file());
        fs::remove_file(t.0.join(file)).unwrap();
    }
    // A collision at the descriptor is reached after four new source writes.
    assert!(publish(&c, &t.0).is_err());
    assert_eq!(fs::read_dir(&t.0).unwrap().count(), 1);
    assert_eq!(fs::read(&path).unwrap(), snapshot);
}
#[test]
fn failed_cli_preflight_preserves_existing_destination() {
    let t = Scratch::new();
    let destination = t.0.join("shader presets with spaces");
    fs::create_dir(&destination).unwrap();
    fs::write(destination.join("keep.json"), "existing preset").unwrap();
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_gen2-slang-import"))
        .arg(fixture("probe.slangp"))
        .arg(&destination)
        .args(["--name", "TEST ; $()", "--love", "/missing/love/executable"])
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("Import failed:"));
    assert_eq!(fs::read_dir(&destination).unwrap().count(), 1);
    assert_eq!(
        fs::read_to_string(destination.join("keep.json")).unwrap(),
        "existing preset"
    );
}
