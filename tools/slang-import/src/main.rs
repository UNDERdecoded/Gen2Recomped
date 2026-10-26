use std::path::PathBuf;
fn run() -> gen2_slang_import::Result<()> {
    let mut args = std::env::args_os().skip(1);
    let preset = PathBuf::from(args.next().ok_or(
        "usage: gen2-slang-import PRESET.slangp DESTINATION --name NAME [--love EXECUTABLE]",
    )?);
    let destination = PathBuf::from(
        args.next()
            .ok_or("missing destination shader-presets directory")?,
    );
    let mut name = None;
    let mut love = PathBuf::from("love");
    while let Some(key) = args.next() {
        match key.to_str() {
            Some("--name") => {
                name = Some(
                    args.next()
                        .ok_or("missing name")?
                        .into_string()
                        .map_err(|_| "name must be UTF-8")?,
                )
            }
            Some("--love") => love = PathBuf::from(args.next().ok_or("missing LÖVE executable")?),
            _ => return Err("unknown argument; expected --name NAME or --love EXECUTABLE".into()),
        }
    }
    let converted = gen2_slang_import::convert(&preset, &name.ok_or("--name NAME is required")?)?;
    gen2_slang_import::preflight(&converted, &love)?;
    let descriptor = gen2_slang_import::publish(&converted, &destination)?;
    println!("Imported {}", descriptor.display());
    Ok(())
}
fn main() {
    if let Err(error) = run() {
        eprintln!("Import failed: {error}");
        std::process::exit(1);
    }
}
