//! Optional desktop browser worker. Network bytes stay in a private, bounded repository tree.
use crate::{Converted, Result};
use serde_json::{Value, json};
use sha1::{Digest, Sha1};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};
pub const REVISION: &str = "d21f8a5abaabc4ee061b6c81f6f1255e09aab32a";
const REPO: &str = "libretro/slang-shaders";
const TOTAL: usize = 16 * 1024 * 1024;
const FILES: usize = 128;
pub type Index = BTreeMap<String, String>;
fn emit(v: Value) -> Result<()> {
    println!("{v}");
    std::io::stdout().flush()?;
    Ok(())
}
fn stopped(root: &Path) -> Result<()> {
    if root.join("cancel").exists() {
        Err("cancelled".into())
    } else {
        Ok(())
    }
}
fn bounded(path: &Path, limit: usize) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    fs::File::open(path)?
        .take((limit + 1) as u64)
        .read_to_end(&mut out)?;
    if out.len() > limit {
        return Err("file limit exceeded".into());
    }
    Ok(out)
}
fn safe(path: &str) -> bool {
    !path.is_empty()
        && path.len() <= 240
        && !path.starts_with('/')
        && path
            .split('/')
            .all(|p| !p.is_empty() && p != "." && p != "..")
        && path
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"_-./ +()[]".contains(&b))
}
fn resolve(parent: &str, child: &str) -> Result<String> {
    if child.starts_with('/') || child.contains('\\') || child.contains(':') {
        return Err("absolute dependency path refused".into());
    }
    let mut parts: Vec<&str> = parent
        .rsplit_once('/')
        .map(|(p, _)| p.split('/').collect())
        .unwrap_or_default();
    for p in child.split('/') {
        match p {
            "." => (),
            ".." => {
                parts.pop().ok_or("dependency escapes repository")?;
            }
            "" => return Err("empty dependency path component".into()),
            _ => parts.push(p),
        }
    }
    let out = parts.join("/");
    if !safe(&out) {
        return Err("invalid dependency path".into());
    }
    Ok(out)
}
fn fetch(url: &str, limit: usize, root: &Path) -> Result<Vec<u8>> {
    stopped(root)?;
    let mut child = Command::new("curl")
        .args([
            "--fail",
            "--silent",
            "--show-error",
            "--location",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--max-redirs",
            "3",
            "--connect-timeout",
            "5",
            "--max-time",
            "15",
            "--user-agent",
            "Gen2Recomped-shaders/1",
            url,
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()?;
    let mut stdout = child.stdout.take().ok_or("download output unavailable")?;
    let mut bytes = Vec::new();
    let mut buffer = [0u8; 8192];
    let result = (|| -> Result<()> {
        loop {
            stopped(root)?;
            let n = stdout.read(&mut buffer)?;
            if n == 0 {
                break;
            }
            if bytes.len() + n > limit {
                return Err("download limit exceeded".into());
            }
            bytes.extend_from_slice(&buffer[..n]);
        }
        Ok(())
    })();
    if result.is_err() {
        let _ = child.kill();
    }
    let status = child.wait()?;
    result?;
    if !status.success() {
        return Err("HTTPS download failed (curl required)".into());
    }
    Ok(bytes)
}
pub fn parse_index(bytes: &[u8]) -> Result<Index> {
    if bytes.len() > 8 * 1024 * 1024 {
        return Err("catalog too large".into());
    }
    let tree: Value = serde_json::from_slice(bytes)?;
    if tree["truncated"] != false {
        return Err("incomplete catalog".into());
    }
    let entries = tree["tree"].as_array().ok_or("missing catalog tree")?;
    if entries.len() > 50_000 {
        return Err("catalog entry limit".into());
    }
    let mut out = Index::new();
    for e in entries {
        if e["type"] != "blob" || !(e["mode"] == "100644" || e["mode"] == "100755") {
            continue;
        }
        let (Some(path), Some(sha)) = (e["path"].as_str(), e["sha"].as_str()) else {
            continue;
        };
        if safe(path) && sha.len() == 40 && sha.bytes().all(|b| b.is_ascii_hexdigit()) {
            out.insert(path.into(), sha.to_ascii_lowercase());
        }
    }
    Ok(out)
}
fn index(root: &Path) -> Result<Index> {
    parse_index(&fetch(
        &format!("https://api.github.com/repos/{REPO}/git/trees/{REVISION}?recursive=1"),
        8 * 1024 * 1024,
        root,
    )?)
}
fn value(line: &str) -> Result<Option<(&str, String)>> {
    let line = line.trim();
    if line.is_empty() || line.starts_with("//") || line.starts_with(';') {
        return Ok(None);
    }
    if let Some(rest) = line.strip_prefix("#reference") {
        return Ok(Some(("#reference", literal(rest)?)));
    }
    if line.starts_with('#') {
        return Ok(None);
    }
    let Some((k, v)) = line.split_once('=') else {
        return Err("unsupported preset line".into());
    };
    if k.trim().is_empty()
        || !k
            .trim()
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_')
    {
        return Err("unsupported preset key".into());
    }
    Ok(Some((k.trim(), literal(v)?)))
}
fn literal(v: &str) -> Result<String> {
    let v = v.trim();
    if let Some(v) = v.strip_prefix('"') {
        let (body, tail) = v.split_once('"').ok_or("unterminated path/value")?;
        if !tail.trim().is_empty()
            && !tail.trim().starts_with('#')
            && !tail.trim().starts_with("//")
        {
            return Err("unsupported trailing value".into());
        }
        Ok(body.to_string())
    } else {
        Ok(v.split("//")
            .next()
            .unwrap_or("")
            .split('#')
            .next()
            .unwrap_or("")
            .trim()
            .to_string())
    }
}
struct Walker<'a, F: FnMut(&str, usize) -> Result<Vec<u8>>> {
    index: &'a Index,
    fetch: F,
    files: BTreeMap<String, Vec<u8>>,
    active: BTreeSet<String>,
    total: usize,
    presets: Vec<(String, Vec<(String, String)>)>,
    textures: BTreeSet<String>,
    expanded: BTreeMap<String, usize>,
}
impl<F: FnMut(&str, usize) -> Result<Vec<u8>>> Walker<'_, F> {
    fn load(&mut self, path: &str, kind: &str, depth: usize) -> Result<()> {
        if depth > 24 || self.active.contains(path) {
            return Err("dependency cycle/depth limit".into());
        }
        if self.files.contains_key(path) {
            return Ok(());
        }
        if self.files.len() >= FILES || !safe(path) {
            return Err("dependency count/path limit".into());
        }
        let sha = self
            .index
            .get(path)
            .ok_or("dependency absent from pinned catalog (symlinks refused)")?;
        let cap = if kind == "png" {
            8 * 1024 * 1024
        } else if kind == "preset" {
            65536
        } else {
            262144
        };
        let bytes = (self.fetch)(path, cap)?;
        if bytes.len() > cap || self.total + bytes.len() > TOTAL {
            return Err("dependency byte limit".into());
        }
        let mut hash = Sha1::new();
        hash.update(format!("blob {}\0", bytes.len()));
        hash.update(&bytes);
        if format!("{:x}", hash.finalize()) != *sha {
            return Err("downloaded blob hash mismatch".into());
        }
        self.total += bytes.len();
        self.active.insert(path.to_string());
        self.files.insert(path.to_string(), bytes.clone());
        if kind != "png" {
            let text = std::str::from_utf8(&bytes)?;
            if text.contains('\0') || text.contains('\u{feff}') {
                return Err("unsupported text encoding".into());
            }
            let mut weight = bytes.len();
            if kind == "preset" {
                if text.contains("/*") || text.contains("*/") {
                    return Err("block comments in presets are unsupported".into());
                }
                let mut entries = Vec::new();
                for line in text.lines() {
                    if let Some((key, v)) = value(line)? {
                        if key == "#reference" {
                            if !v.ends_with(".slangp") {
                                return Err("preset reference extension".into());
                            }
                            self.load(&resolve(path, &v)?, "preset", depth + 1)?;
                        } else if key == "textures" {
                            for id in v.split(';').filter(|s| !s.is_empty()) {
                                if !crate::identifier(id) {
                                    return Err("unsupported LUT name".into());
                                }
                                self.textures.insert(id.into());
                            }
                        } else if key == "shaders" && !(1..=8).contains(&v.parse::<usize>()?) {
                            return Err("pass count limit".into());
                        }
                        entries.push((key.to_string(), v));
                    }
                }
                self.presets.push((path.to_string(), entries));
            } else {
                for line in text.lines() {
                    let line = line.trim();
                    if crate::rx(r"^#\s+(include|pragma\s+include_optional)\b").is_match(line) {
                        return Err("unsupported include directive".into());
                    }
                    if line.starts_with("#pragma include_optional") {
                        return Err("optional shader includes are unsupported".into());
                    }
                    if let Some(rest) = line.strip_prefix("#include") {
                        if !rest.trim_start().starts_with('"') {
                            return Err("only literal shader includes are supported".into());
                        }
                        let child = resolve(path, &literal(rest)?)?;
                        self.load(&child, "shader", depth + 1)?;
                        weight += self.expanded.get(&child).copied().unwrap_or(0);
                        if weight > 2 * 1024 * 1024 {
                            return Err("expanded include byte limit".into());
                        }
                    }
                }
            }
            self.expanded.insert(path.into(), weight);
        }
        self.active.remove(path);
        Ok(())
    }
}
/// Walk references, shader includes and inherited/overridden texture keys before librashader sees any file.
pub fn collect<F: FnMut(&str, usize) -> Result<Vec<u8>>>(
    index: &Index,
    path: &str,
    fetch: F,
) -> Result<BTreeMap<String, Vec<u8>>> {
    if !path.ends_with(".slangp") {
        return Err("expected slangp".into());
    }
    let mut w = Walker {
        index,
        fetch,
        files: BTreeMap::new(),
        active: BTreeSet::new(),
        total: 0,
        presets: Vec::new(),
        textures: BTreeSet::new(),
        expanded: BTreeMap::new(),
    };
    w.load(path, "preset", 0)?;
    for (preset, entries) in w.presets.clone() {
        for (key, v) in entries {
            if key
                .strip_prefix("shader")
                .is_some_and(|n| !n.is_empty() && n.bytes().all(|c| c.is_ascii_digit()))
            {
                if !v.ends_with(".slang") {
                    return Err("unsupported shader extension".into());
                }
                w.load(&resolve(&preset, &v)?, "shader", 0)?;
            } else if w.textures.contains(&key) {
                if !v.ends_with(".png") {
                    return Err("only PNG LUTs are supported".into());
                }
                w.load(&resolve(&preset, &v)?, "png", 0)?;
            }
        }
    }
    Ok(w.files)
}
fn write_new(path: &Path, bytes: &[u8]) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut f = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)?;
    f.write_all(bytes)?;
    f.sync_all()?;
    Ok(())
}
fn prepare(
    root: &Path,
    index: &Index,
    path: &str,
    name: &str,
) -> Result<(Converted, BTreeMap<String, Vec<u8>>)> {
    let mut files = collect(index, path, |p, n| {
        fetch(
            &format!(
                "https://raw.githubusercontent.com/{REPO}/{REVISION}/{}",
                p.replace(' ', "%20")
                    .replace('[', "%5B")
                    .replace(']', "%5D")
            ),
            n,
            root,
        )
    })?;
    // Preserve original sources and repository/directory notices beside the installed artifact.
    let mut directories = BTreeSet::from([String::new()]);
    for p in files.keys() {
        let mut dir = Path::new(p).parent();
        while let Some(d) = dir {
            directories.insert(d.to_string_lossy().to_string());
            dir = d.parent();
        }
    }
    for dir in directories {
        for notice in [
            "LICENSE",
            "LICENSE.md",
            "LICENSE.txt",
            "license.txt",
            "COPYING",
            "COPYING.txt",
            "README.md",
        ] {
            let name = if dir.is_empty() {
                notice.to_string()
            } else {
                format!("{dir}/{notice}")
            };
            if index.contains_key(&name) && !files.contains_key(&name) {
                let bytes = fetch(
                    &format!("https://raw.githubusercontent.com/{REPO}/{REVISION}/{name}"),
                    262144,
                    root,
                )?;
                let mut hash = Sha1::new();
                hash.update(format!("blob {}\0", bytes.len()));
                hash.update(&bytes);
                if format!("{:x}", hash.finalize()) != index[&name] {
                    return Err("notice hash mismatch".into());
                }
                files.insert(name, bytes);
            }
        }
    }
    if files.len() > FILES || files.values().map(|v| v.len()).sum::<usize>() > TOTAL {
        return Err("source archive budget".into());
    }
    let source = root.join("source");
    for (p, bytes) in &files {
        write_new(&source.join(p), bytes)?;
    }

    stopped(root)?;
    emit(json!({"kind":"status","message":"Converting shader passes"}))?;
    Ok((crate::convert(&source.join(path), name)?, files))
}
fn staged(c: &Converted, root: &Path) -> Result<()> {
    let (meta, files) = crate::bundle(c, "prepared", true)?;
    let directory = root.join("prepared");
    for (name, bytes) in files {
        write_new(&directory.join(name), &bytes)?;
    }
    write_new(
        &directory.join("prepared.json"),
        &serde_json::to_vec(&meta)?,
    )?;
    Ok(())
}
fn verify_staged(c: &Converted, root: &Path) -> Result<()> {
    let (meta, files) = crate::bundle(c, "prepared", true)?;
    for (name, bytes) in files {
        if bounded(&root.join("prepared").join(name), bytes.len())? != bytes {
            return Err("prepared resource changed after validation".into());
        }
    }
    if bounded(&root.join("prepared/prepared.json"), 16384)? != serde_json::to_vec(&meta)? {
        return Err("prepared descriptor changed".into());
    }
    Ok(())
}
fn archive_sources(
    files: &BTreeMap<String, Vec<u8>>,
    index: &Index,
    preset: &str,
    destination: &Path,
) -> Result<Option<PathBuf>> {
    let mut hash = Sha1::new();
    hash.update(preset);
    let path_hash = format!("{:x}", hash.finalize());
    let directory = destination
        .join("sources")
        .join(format!("{REVISION}-{}", &path_hash[..16]));
    fs::create_dir_all(destination.join("sources"))?;
    let mut expected = files.clone();
    let manifest = json!({"repository":REPO,"revision":REVISION,"preset":preset,"files":files.keys().map(|p|json!({"path":p,"blob":index[p]})).collect::<Vec<_>>()});
    expected.insert(
        "provenance.json".into(),
        serde_json::to_vec_pretty(&manifest)?,
    );
    match fs::create_dir(&directory) {
        Ok(()) => {
            let result = (|| -> Result<()> {
                for (name, bytes) in &expected {
                    write_new(&directory.join(name), bytes)?;
                }
                Ok(())
            })();
            if result.is_err() {
                let _ = fs::remove_dir_all(&directory);
            }
            result?;
            Ok(Some(directory))
        }
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
            for (name, bytes) in expected {
                if bounded(&directory.join(name), bytes.len())? != bytes {
                    return Err("existing source archive differs".into());
                }
            }
            Ok(None)
        }
        Err(e) => Err(e.into()),
    }
}
/// Request files are generated by the desktop worker; a source preset never supplies host paths.
pub fn request(path: &Path) -> Result<()> {
    let root = path.parent().ok_or("request directory unavailable")?;
    let req: Value = serde_json::from_slice(&bounded(path, 16384)?)?;
    // Claim both private directories exclusively before any operation or cleanup.
    let source = root.join("source");
    let prepared = root.join("prepared");
    fs::create_dir(&source)?;
    if let Err(error) = fs::create_dir(&prepared) {
        let _ = fs::remove_dir(&source);
        return Err(error.into());
    }
    let result = (|| -> Result<()> {
        stopped(root)?;
        emit(json!({"kind":"status","message":"Reading pinned shader catalog"}))?;
        let idx = index(root)?;
        if req["op"] == "catalog" {
            let entries:Vec<_>=idx.keys().filter(|p|p.starts_with("handheld/")&&p.ends_with(".slangp")).map(|p|json!({"path":p,"name":p.rsplit('/').next().unwrap().trim_end_matches(".slangp")})).collect();
            emit(json!({"kind":"catalog","revision":REVISION,"entries":entries}))?;
            return Ok(());
        }
        if req["op"] != "install" {
            return Err("unknown browser request".into());
        }
        let preset = req["path"].as_str().ok_or("preset path required")?;
        if !preset.starts_with("handheld/") || !idx.contains_key(preset) {
            return Err("preset absent from catalog".into());
        }
        let name = preset
            .rsplit('/')
            .next()
            .unwrap()
            .trim_end_matches(".slangp");
        let (c, files) = prepare(root, &idx, preset, name)?;
        stopped(root)?;
        staged(&c, root)?;
        emit(json!({"kind":"ready"}))?;
        let start = Instant::now();
        while !root.join("approve").is_file() {
            stopped(root)?;
            if start.elapsed() > Duration::from_secs(45) {
                return Err("GPU validation timed out".into());
            }
            thread::sleep(Duration::from_millis(50));
        }
        stopped(root)?;
        verify_staged(&c, root)?;
        let dest = PathBuf::from(req["destination"].as_str().ok_or("destination required")?);
        let created_archive = archive_sources(&files, &idx, preset, &dest)?;
        let result = (|| -> Result<PathBuf> {
            stopped(root)?;
            if let Some(path) = crate::existing(&c, &dest) {
                Ok(path)
            } else {
                crate::publish_checked(&c, &dest, || stopped(root))
            }
        })();
        if result.is_err()
            && let Some(path) = created_archive
        {
            let _ = fs::remove_dir_all(path);
        }
        let descriptor = result?;
        emit(
            json!({"kind":"installed","id":format!("local:{}",descriptor.file_stem().unwrap().to_string_lossy())}),
        )?;
        Ok(())
    })();
    // Only private trees created by this request are removed; preset destination is never cleaned here.
    for name in ["source", "prepared"] {
        let _ = fs::remove_dir_all(root.join(name));
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    static NEXT_TEMP: AtomicUsize = AtomicUsize::new(0);
    struct Temp(PathBuf);
    impl Temp {
        fn new() -> Self {
            let p = std::env::temp_dir().join(format!(
                "shader-job-test-{}-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos(),
                NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir(&p).unwrap();
            Self(p)
        }
    }
    impl Drop for Temp {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    fn converted() -> Converted {
        crate::convert(
            &Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/graph.slangp"),
            "GRAPH",
        )
        .unwrap()
    }
    #[test]
    fn prepared_mutation_is_refused_and_existing_publication_requires_exact_bytes() {
        let t = Temp::new();
        let c = converted();
        staged(&c, &t.0).unwrap();
        verify_staged(&c, &t.0).unwrap();
        fs::write(t.0.join("prepared/prepared-p0-f.glsl"), "changed").unwrap();
        assert!(verify_staged(&c, &t.0).is_err());
        let dest = t.0.join("destination");
        let path = crate::publish(&c, &dest).unwrap();
        assert_eq!(crate::existing(&c, &dest).unwrap(), path);
        fs::write(&path, "modified").unwrap();
        assert!(crate::existing(&c, &dest).is_none());
        assert!(crate::publish(&c, &dest).is_err());
        assert_eq!(fs::read(&path).unwrap(), b"modified");
    }
    #[test]
    fn cancellation_during_publication_rolls_back_only_owned_files() {
        let t = Temp::new();
        let c = converted();
        fs::write(t.0.join("keep.json"), "keep").unwrap();
        let mut n = 0;
        assert!(
            crate::publish_checked(&c, &t.0, || {
                n += 1;
                if n == 5 {
                    Err("cancelled".into())
                } else {
                    Ok(())
                }
            })
            .is_err()
        );
        assert_eq!(fs::read_dir(&t.0).unwrap().count(), 1);
        assert_eq!(fs::read(t.0.join("keep.json")).unwrap(), b"keep");
    }
    #[test]
    fn failed_request_never_cleans_preexisting_private_or_destination_files() {
        let t = Temp::new();
        fs::write(t.0.join("request.json"), r#"{"op":"catalog"}"#).unwrap();
        fs::create_dir(t.0.join("source")).unwrap();
        fs::write(t.0.join("source/keep"), "keep").unwrap();
        assert!(request(&t.0.join("request.json")).is_err());
        assert_eq!(fs::read(t.0.join("source/keep")).unwrap(), b"keep");
    }
    #[test]
    fn source_archive_preserves_exact_notices_and_refuses_modified_existing_archive() {
        let t = Temp::new();
        let files = BTreeMap::from([("LICENSE".into(), b"notice".to_vec())]);
        let index = Index::from([("LICENSE".into(), "blob".into())]);
        let archive = archive_sources(&files, &index, "handheld/test.slangp", &t.0)
            .unwrap()
            .unwrap();
        assert_eq!(fs::read(archive.join("LICENSE")).unwrap(), b"notice");
        assert!(
            archive_sources(&files, &index, "handheld/test.slangp", &t.0)
                .unwrap()
                .is_none()
        );
        fs::write(archive.join("LICENSE"), "modified").unwrap();
        assert!(archive_sources(&files, &index, "handheld/test.slangp", &t.0).is_err());
    }
}
