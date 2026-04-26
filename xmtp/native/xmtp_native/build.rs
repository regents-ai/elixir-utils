fn main() {
    let target = std::env::var("TARGET").unwrap_or_default();

    if target.contains("linux") {
        println!("cargo:rustc-link-arg=-Wl,--allow-multiple-definition");
    } else if target.contains("windows") && target.contains("msvc") {
        println!("cargo:rustc-link-arg=/FORCE:MULTIPLE");
    } else if target.contains("apple") {
        println!("cargo:rustc-link-arg=-Wl,-multiply_defined,suppress");
    }
}
