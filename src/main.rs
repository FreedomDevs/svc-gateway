mod config;

use config::loader::load_config;

#[tokio::main]
async fn main() {
    let config = load_config("config.yaml");

    println!("Loaded config: {:#?}", config);
}

