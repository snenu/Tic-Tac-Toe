use async_graphql::{Request, Response};
use linera_sdk::linera_base_types::{ChainId, ContractAbi, ServiceAbi};
use serde::{Deserialize, Serialize};

pub struct TictactoeAbi;

impl ContractAbi for TictactoeAbi {
    type Operation = Operation;
    type Response = ();
}

impl ServiceAbi for TictactoeAbi {
    type Query = Request;
    type QueryResponse = Response;
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct TictactoeParameters {}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct InstantiationArgument;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, async_graphql::Enum)]
pub enum GameStatus {
    WaitingForPlayer,
    Active,
    Ended,
    Draw,
}

#[derive(Debug, Clone, Serialize, Deserialize, async_graphql::SimpleObject)]
#[graphql(rename_fields = "camelCase")]
pub struct PlayerInfo {
    pub chain_id: String,
    pub name: String,
}

/// Board: 9 elements, -1 = empty, 0 = host/X, 1 = guest/O (for GraphQL).
/// Stored on-chain as [Option<u8>; 9] with None = empty, Some(0) = X, Some(1) = O.
#[derive(Debug, Clone, Serialize, Deserialize, async_graphql::SimpleObject)]
#[graphql(rename_fields = "camelCase")]
pub struct Game {
    pub match_id: String,
    pub host_chain_id: String,
    pub status: GameStatus,
    pub players: Vec<PlayerInfo>,
    /// 9 cells: -1 empty, 0 = X (host), 1 = O (guest)
    pub board: Vec<i32>,
    /// 0 = host/X, 1 = guest/O
    pub current_turn_index: u8,
    pub winner_chain_id: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum Operation {
    CreateMatch { host_name: String },
    JoinMatch {
        host_chain_id: String,
        player_name: String,
    },
    MakeMove { row: u8, col: u8 },
    LeaveMatch,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum CrossChainMessage {
    JoinRequest {
        player_chain_id: ChainId,
        player_name: String,
    },
    InitialStateSync { game: Game },
    GameSync { game: Game },
    LeaveNotice { player_chain_id: ChainId },
}
