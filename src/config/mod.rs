pub mod loader;

use serde::Deserialize;
use std::collections::HashMap;
use std::collections::HashSet;

#[derive(Debug, Deserialize)]
pub struct GatewayConfig {
    pub gateway: GatewaySettings,
    pub services: HashMap<String, ServiceConfig>,
    pub allowed_server_tokens: HashSet<String>,
}

#[derive(Debug, Deserialize)]
pub struct GatewaySettings {
    pub host: String,
    pub max_body_size: usize,
    pub trusted_proxy_ips: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct ServiceConfig {
    #[serde(rename = "baseUrl")]
    pub base_url: String,

    pub routes: Vec<RouteConfig>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct RouteConfig {
    pub path: String,
    pub method: String,
    pub allow_roles: Option<HashSet<String>>,
    pub special_allow_roles: Option<HashSet<String>>,
}
