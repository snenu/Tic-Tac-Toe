use linera_sdk::views::{linera_views, RegisterView, RootView, ViewStorageContext};

use tictactoe::Game;

#[derive(RootView)]
#[view(context = ViewStorageContext)]
pub struct TictactoeState {
    pub game: RegisterView<Option<Game>>,
    pub last_notification: RegisterView<Option<String>>,
}
