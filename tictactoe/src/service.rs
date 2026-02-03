#![cfg_attr(target_arch = "wasm32", no_main)]

mod state;

use std::sync::Arc;

use async_graphql::{EmptySubscription, Object, Request, Response, Schema};
use linera_sdk::{linera_base_types::WithServiceAbi, views::View, Service, ServiceRuntime};

use tictactoe::{Game, GameStatus, Operation, TictactoeAbi, TictactoeParameters};

use self::state::TictactoeState;

linera_sdk::service!(TictactoeService);

pub struct TictactoeService {
    state: TictactoeState,
    runtime: Arc<ServiceRuntime<Self>>,
}

impl WithServiceAbi for TictactoeService {
    type Abi = TictactoeAbi;
}

impl Service for TictactoeService {
    type Parameters = TictactoeParameters;

    async fn new(runtime: ServiceRuntime<Self>) -> Self {
        let state = TictactoeState::load(runtime.root_view_storage_context())
            .await
            .expect("Failed to load state");
        TictactoeService {
            state,
            runtime: Arc::new(runtime),
        }
    }

    async fn handle_query(&self, request: Request) -> Response {
        let game = self.state.game.get().clone();
        let last_notification = self.state.last_notification.get().clone();
        let schema = Schema::build(
            QueryRoot {
                game: game.clone(),
                chain_id: self.runtime.chain_id().to_string(),
                last_notification,
            },
            MutationRoot {
                runtime: self.runtime.clone(),
            },
            EmptySubscription,
        )
        .finish();
        schema.execute(request).await
    }
}

struct QueryRoot {
    game: Option<Game>,
    chain_id: String,
    last_notification: Option<String>,
}

#[Object]
impl QueryRoot {
    async fn game(&self) -> Option<&Game> {
        self.game.as_ref()
    }

    async fn match_status(&self) -> Option<GameStatus> {
        self.game.as_ref().map(|g| g.status)
    }

    async fn is_host(&self) -> bool {
        self.game
            .as_ref()
            .map(|g| g.host_chain_id == self.chain_id)
            .unwrap_or(false)
    }

    async fn opponent_chain_id(&self) -> Option<String> {
        let game = self.game.as_ref()?;
        game.players
            .iter()
            .find(|p| p.chain_id != self.chain_id)
            .map(|p| p.chain_id.clone())
    }

    async fn board(&self) -> Option<Vec<i32>> {
        self.game.as_ref().map(|g| g.board.clone())
    }

    async fn current_turn_index(&self) -> Option<i32> {
        self.game.as_ref().map(|g| g.current_turn_index as i32)
    }

    async fn current_turn_chain_id(&self) -> Option<String> {
        let game = self.game.as_ref()?;
        let idx = game.current_turn_index as usize;
        if game.players.len() > idx {
            Some(game.players[idx].chain_id.clone())
        } else {
            None
        }
    }

    async fn winner_chain_id(&self) -> Option<String> {
        self.game.as_ref().and_then(|g| g.winner_chain_id.clone())
    }

    async fn last_notification(&self) -> Option<String> {
        self.last_notification.clone()
    }
}

struct MutationRoot {
    runtime: Arc<ServiceRuntime<TictactoeService>>,
}

#[Object]
impl MutationRoot {
    async fn create_match(&self, host_name: String) -> String {
        self.runtime
            .schedule_operation(&Operation::CreateMatch {
                host_name: host_name.clone(),
            });
        format!("Match created by '{}'", host_name)
    }

    async fn join_match(&self, host_chain_id: String, player_name: String) -> String {
        self.runtime.schedule_operation(&Operation::JoinMatch {
            host_chain_id: host_chain_id.clone(),
            player_name: player_name.clone(),
        });
        format!("Join request sent to {}", host_chain_id)
    }

    async fn make_move(&self, row: u8, col: u8) -> String {
        self.runtime.schedule_operation(&Operation::MakeMove { row, col });
        "Move submitted".to_string()
    }

    async fn leave_match(&self) -> String {
        self.runtime.schedule_operation(&Operation::LeaveMatch);
        "Leave requested".to_string()
    }
}
