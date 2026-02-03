#![cfg_attr(target_arch = "wasm32", no_main)]

mod state;

use tictactoe::{
    CrossChainMessage, Game, GameStatus, Operation, PlayerInfo, TictactoeAbi,
    InstantiationArgument, TictactoeParameters,
};
use linera_sdk::{
    linera_base_types::WithContractAbi,
    views::{RootView, View},
    Contract, ContractRuntime,
};

use self::state::TictactoeState;

linera_sdk::contract!(TictactoeContract);

pub struct TictactoeContract {
    state: TictactoeState,
    runtime: ContractRuntime<Self>,
}

impl WithContractAbi for TictactoeContract {
    type Abi = TictactoeAbi;
}

impl TictactoeContract {
    fn is_host(&mut self, game: &Game) -> bool {
        game.host_chain_id == self.runtime.chain_id().to_string()
    }

    fn opponent_chain_id(&mut self, game: &Game) -> Option<linera_sdk::linera_base_types::ChainId> {
        let self_chain = self.runtime.chain_id().to_string();
        game.players
            .iter()
            .find(|p| p.chain_id != self_chain)
            .and_then(|p| p.chain_id.parse().ok())
    }

    fn can_play(&self, game: &Game) -> bool {
        game.status == GameStatus::Active && game.players.len() == 2
    }

    /// Returns winner cell value (0 or 1) if any, else None. Draw = None with full board.
    fn check_winner(board: &[i32]) -> Option<i32> {
        let lines: [[usize; 3]; 8] = [
            [0, 1, 2],
            [3, 4, 5],
            [6, 7, 8],
            [0, 3, 6],
            [1, 4, 7],
            [2, 5, 8],
            [0, 4, 8],
            [2, 4, 6],
        ];
        for indices in &lines {
            let a = board[indices[0]];
            let b = board[indices[1]];
            let c = board[indices[2]];
            if a >= 0 && a == b && b == c {
                return Some(a);
            }
        }
        None
    }

    fn is_board_full(board: &[i32]) -> bool {
        board.iter().all(|&c| c >= 0)
    }

    fn current_turn_chain_id(game: &Game) -> Option<&str> {
        if game.players.len() <= game.current_turn_index as usize {
            return None;
        }
        Some(&game.players[game.current_turn_index as usize].chain_id)
    }
}

impl Contract for TictactoeContract {
    type Message = CrossChainMessage;
    type InstantiationArgument = InstantiationArgument;
    type Parameters = TictactoeParameters;
    type EventValue = ();

    async fn load(runtime: ContractRuntime<Self>) -> Self {
        let state = TictactoeState::load(runtime.root_view_storage_context())
            .await
            .expect("Failed to load state");
        TictactoeContract { state, runtime }
    }

    async fn instantiate(&mut self, _argument: InstantiationArgument) {
        self.state.game.set(None);
        self.state.last_notification.set(None);
    }

    async fn execute_operation(&mut self, operation: Operation) {
        match operation {
            Operation::CreateMatch { host_name } => {
                let chain_id = self.runtime.chain_id().to_string();
                let match_id = self.runtime.system_time().micros().to_string();
                let game = Game {
                    match_id,
                    host_chain_id: chain_id.clone(),
                    status: GameStatus::WaitingForPlayer,
                    players: vec![PlayerInfo {
                        chain_id: chain_id.clone(),
                        name: host_name,
                    }],
                    board: vec![-1; 9],
                    current_turn_index: 0,
                    winner_chain_id: None,
                };
                self.state.game.set(Some(game));
                self.state.last_notification.set(None);
            }

            Operation::JoinMatch {
                host_chain_id,
                player_name,
            } => {
                let target_chain: linera_sdk::linera_base_types::ChainId = host_chain_id
                    .parse()
                    .expect("Invalid host chain ID");
                let player_chain_id = self.runtime.chain_id();
                self.runtime.send_message(
                    target_chain,
                    CrossChainMessage::JoinRequest {
                        player_chain_id,
                        player_name,
                    },
                );
            }

            Operation::MakeMove { row, col } => {
                let mut game = self.state.game.get().clone().expect("Match not found");
                if !self.can_play(&game) {
                    panic!("Match not ready");
                }
                if row >= 3 || col >= 3 {
                    panic!("Invalid cell");
                }
                let idx = (row as usize) * 3 + (col as usize);
                if game.board[idx] >= 0 {
                    panic!("Cell already taken");
                }
                let my_chain = self.runtime.chain_id().to_string();
                let current_chain = Self::current_turn_chain_id(&game).unwrap_or("");
                if my_chain != current_chain {
                    panic!("Not your turn");
                }

                game.board[idx] = game.current_turn_index as i32;

                if let Some(winner_val) = Self::check_winner(&game.board) {
                    game.status = GameStatus::Ended;
                    game.winner_chain_id = Some(
                        game.players[winner_val as usize]
                            .chain_id
                            .clone(),
                    );
                } else if Self::is_board_full(&game.board) {
                    game.status = GameStatus::Draw;
                } else {
                    game.current_turn_index = 1 - game.current_turn_index;
                }

                self.state.game.set(Some(game.clone()));

                if let Some(opponent) = self.opponent_chain_id(&game) {
                    self.runtime
                        .send_message(opponent, CrossChainMessage::GameSync { game });
                }
            }

            Operation::LeaveMatch => {
                if let Some(game) = self.state.game.get().clone() {
                    if let Some(opponent) = self.opponent_chain_id(&game) {
                        let player_chain_id = self.runtime.chain_id();
                        self.runtime.send_message(
                            opponent,
                            CrossChainMessage::LeaveNotice { player_chain_id },
                        );
                    }
                }
                self.state.game.set(None);
                self.state.last_notification.set(None);
            }
        }
    }

    async fn execute_message(&mut self, message: Self::Message) {
        match message {
            CrossChainMessage::JoinRequest {
                player_chain_id,
                player_name,
            } => {
                let mut game = self.state.game.get().clone().expect("Match not found");
                if !self.is_host(&game) {
                    panic!("Only host can accept joins");
                }
                if game.status != GameStatus::WaitingForPlayer {
                    panic!("Match not joinable");
                }
                if game.players.len() >= 2 {
                    panic!("Match full");
                }

                game.players.push(PlayerInfo {
                    chain_id: player_chain_id.to_string(),
                    name: player_name,
                });
                game.status = GameStatus::Active;
                self.state.game.set(Some(game.clone()));
                self.state
                    .last_notification
                    .set(Some("Player joined".to_string()));
                self.runtime.send_message(
                    player_chain_id,
                    CrossChainMessage::InitialStateSync { game },
                );
            }

            CrossChainMessage::InitialStateSync { game } => {
                self.state.game.set(Some(game));
                self.state
                    .last_notification
                    .set(Some("Match ready".to_string()));
            }

            CrossChainMessage::GameSync { game } => {
                self.state.game.set(Some(game));
            }

            CrossChainMessage::LeaveNotice { .. } => {
                self.state.game.set(None);
                self.state
                    .last_notification
                    .set(Some("Opponent left".to_string()));
            }
        }
    }

    async fn process_streams(
        &mut self,
        _streams: Vec<linera_sdk::linera_base_types::StreamUpdate>,
    ) {
    }

    async fn store(mut self) {
        let _ = self.state.save().await;
    }
}
