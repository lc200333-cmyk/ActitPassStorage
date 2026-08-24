pub use sync_core::{merge_last_write_wins, ChangeRecord, ConflictRecord, MergeResult};
pub use vault_core::{
    built_in_templates, FieldType, Item, ItemFieldValue, Template, TemplateField,
};

pub fn core_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}
