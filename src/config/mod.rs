pub mod loader;

use serde::Deserialize;
use std::collections::HashMap;

#[derive(Debug, Deserialize)]
pub struct GatewayConfig {
    pub gateway: GatewaySettings,
    pub services: HashMap<String, ServiceConfig>,
}

#[derive(Debug, Deserialize)]
pub struct GatewaySettings {
    pub host: String,
    pub port: u16,
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
    pub auth: AuthType,
    pub roles: Option<Vec<String>>,
}

#[derive(Debug, Deserialize, Clone, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum AuthType {
    Required,
    None,
}
