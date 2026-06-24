#[derive(Debug, Clone, serde::Serialize)]
pub struct AppEvent {
    pub channel_name: String,
    pub message: String,
}
