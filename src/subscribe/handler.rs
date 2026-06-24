/*use axum::{
    extract::{Request, State},
    response::{Sse, sse::Event},
};
use futures::stream::{self, Stream};
use std::convert::Infallible;

use crate::AppState;

pub async fn subscribe_handler(
    State(state): State<AppState>,
    req: Request,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
}*/
