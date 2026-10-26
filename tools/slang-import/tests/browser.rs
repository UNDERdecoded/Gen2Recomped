use gen2_slang_import::browser::{Index, collect, parse_index};
use sha1::{Digest, Sha1};
use std::collections::BTreeMap;
fn files(pairs: &[(&str, &str)]) -> (Index, BTreeMap<String, Vec<u8>>) {
    let mut index = Index::new();
    let mut files = BTreeMap::new();
    for (path, text) in pairs {
        let mut hash = Sha1::new();
        hash.update(format!("blob {}\0", text.len()));
        hash.update(text);
        index.insert(path.to_string(), format!("{:x}", hash.finalize()));
        files.insert(path.to_string(), text.as_bytes().to_vec());
    }
    (index, files)
}
fn walk(pairs: &[(&str, &str)]) -> gen2_slang_import::Result<BTreeMap<String, Vec<u8>>> {
    let (i, f) = files(pairs);
    collect(&i, "handheld/test.slangp", |p, _| {
        Ok(f.get(p).unwrap().clone())
    })
}
#[test]
fn resolves_references_includes_and_inherited_lut_overrides_within_pinned_repository() {
    let out = walk(&[
        (
            "handheld/test.slangp",
            "#reference base.slangp\nTint=../lut/override.png",
        ),
        (
            "handheld/base.slangp",
            "shaders=1\nshader0=shaders/test.slang\ntextures=Tint\nTint=../lut/default.png",
        ),
        (
            "handheld/shaders/test.slang",
            "#version 450\n#include \"../../include/common.inc\"",
        ),
        ("include/common.inc", "float value=1.0;"),
        ("lut/override.png", "override"),
        ("lut/default.png", "default"),
    ])
    .unwrap();
    assert_eq!(out.len(), 6);
    assert!(out.contains_key("lut/override.png"));
}
#[test]
fn rejects_escapes_cycles_unsupported_syntax_and_untracked_dependencies_before_parser() {
    for text in [
        "shaders=1\nshader0=../../escape.slang",
        "#reference /absolute.slangp",
        "#reference C:/escape.slangp",
        "#reference test.slangp",
        "/* hidden */ #reference ../../escape.slangp",
        "shader0\n=../../escape.slang",
        "shaders=1000000000",
        "shaders=1\nshader0=missing.slang",
        "shaders=1\ntextures=Tint\nTint=../../outside.png",
        "\u{feff}#reference ../../escape.slangp",
        "#reference \"unterminated.slangp",
    ] {
        assert!(walk(&[("handheld/test.slangp", text)]).is_err(), "{text}");
    }
    for source in [
        "#include MACRO",
        "#include \"../../outside.inc\"",
        "#include \"test.slang\"",
        "#pragma include_optional \"../../secret\"",
    ] {
        assert!(
            walk(&[
                ("handheld/test.slangp", "shaders=1\nshader0=test.slang"),
                ("handheld/test.slang", source)
            ])
            .is_err(),
            "{source}"
        );
    }
}
#[test]
fn verifies_blob_hash_and_refuses_symlinks_and_truncated_catalogs() {
    let tree=br#"{"truncated":false,"tree":[{"type":"blob","mode":"120000","path":"handheld/link.slangp","sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},{"type":"blob","mode":"100644","path":"../escape.slangp","sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}"#;
    assert!(parse_index(tree).unwrap().is_empty());
    assert!(parse_index(br#"{"truncated":true,"tree":[]}"#).is_err());
    let (i, _) = files(&[("handheld/test.slangp", "shaders=1")]);
    assert!(
        collect(&i, "handheld/test.slangp", |_, _| Ok(b"tampered".to_vec()))
            .err()
            .unwrap()
            .to_string()
            .contains("hash")
    );
}
#[test]
fn caps_files_depth_raw_and_expanded_includes() {
    let mut pairs = vec![(
        "handheld/test.slangp".to_string(),
        "shaders=1\nshader0=0.slang".to_string(),
    )];
    for n in 0..26 {
        pairs.push((
            format!("handheld/{n}.slang"),
            format!("#include \"{}.slang\"", n + 1),
        ));
    }
    let refs: Vec<_> = pairs
        .iter()
        .map(|(a, b)| (a.as_str(), b.as_str()))
        .collect();
    assert!(walk(&refs).is_err());
    let long = " ".repeat(65537);
    assert!(
        walk(&[("handheld/test.slangp", &long)])
            .err()
            .unwrap()
            .to_string()
            .contains("byte limit")
    );
    let mut pairs = vec![(
        "handheld/test.slangp".to_string(),
        "shaders=1\nshader0=0.slang".to_string(),
    )];
    for n in 0..12 {
        pairs.push((
            format!("handheld/{n}.slang"),
            format!("#include \"{}.slang\"\n#include \"{}.slang\"", n + 1, n + 1),
        ));
    }
    pairs.push(("handheld/12.slang".to_string(), " ".repeat(1024)));
    let refs: Vec<_> = pairs
        .iter()
        .map(|(a, b)| (a.as_str(), b.as_str()))
        .collect();
    assert!(walk(&refs).err().unwrap().to_string().contains("expanded"));
}
