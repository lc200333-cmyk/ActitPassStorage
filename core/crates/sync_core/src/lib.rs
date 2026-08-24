use vault_core::Item;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChangeRecord {
    pub change_id: String,
    pub device_id: String,
    pub item: Item,
    pub modified_at_ms: i64,
    pub base_revision: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConflictRecord {
    pub conflict_id: String,
    pub item_id: String,
    pub local_change_id: String,
    pub remote_change_id: String,
    pub winner_change_id: String,
    pub created_at_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MergeResult {
    pub winner: Item,
    pub conflict: Option<ConflictRecord>,
}

pub fn merge_last_write_wins(
    local: &ChangeRecord,
    remote: &ChangeRecord,
    created_at_ms: i64,
) -> MergeResult {
    let remote_wins = remote.modified_at_ms > local.modified_at_ms
        || (remote.modified_at_ms == local.modified_at_ms && remote.change_id > local.change_id);
    let winner = if remote_wins {
        remote.item.clone()
    } else {
        local.item.clone()
    };
    let winner_change_id = if remote_wins {
        &remote.change_id
    } else {
        &local.change_id
    };
    let conflict = if local.item.id == remote.item.id && local.change_id != remote.change_id {
        Some(ConflictRecord {
            conflict_id: format!("conflict_{}_{}", local.change_id, remote.change_id),
            item_id: local.item.id.clone(),
            local_change_id: local.change_id.clone(),
            remote_change_id: remote.change_id.clone(),
            winner_change_id: winner_change_id.clone(),
            created_at_ms,
        })
    } else {
        None
    };
    MergeResult { winner, conflict }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(title: &str, modified_at_ms: i64) -> Item {
        Item {
            id: "item_1".to_owned(),
            template_id: "tpl_password".to_owned(),
            title: title.to_owned(),
            category: "Тест".to_owned(),
            color_id: "blue".to_owned(),
            values: vec![],
            modified_at_ms,
        }
    }

    #[test]
    fn later_change_wins_and_conflict_is_recorded() {
        let local = ChangeRecord {
            change_id: "change_a".to_owned(),
            device_id: "device_a".to_owned(),
            item: item("Старое", 10),
            modified_at_ms: 10,
            base_revision: "rev_1".to_owned(),
        };
        let remote = ChangeRecord {
            change_id: "change_b".to_owned(),
            device_id: "device_b".to_owned(),
            item: item("Новое", 20),
            modified_at_ms: 20,
            base_revision: "rev_1".to_owned(),
        };
        let result = merge_last_write_wins(&local, &remote, 30);
        assert_eq!(result.winner.title, "Новое");
        assert!(result.conflict.is_some());
    }
}
