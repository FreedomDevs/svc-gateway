use crate::config::GatewayConfig;
use std::fs;

pub fn load_config(path: &str) -> GatewayConfig {
    let content = fs::read_to_string(path).expect("Cannot read config file");

    serde_yaml::from_str(&content).expect("Invalid config format")
}

