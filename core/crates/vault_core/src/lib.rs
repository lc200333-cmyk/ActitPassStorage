#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TemplateField {
    pub id: String,
    pub label: String,
    pub field_type: FieldType,
    pub required: bool,
    pub secret: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FieldType {
    Text,
    Password,
    MultilineNote,
    Url,
    Email,
    Phone,
    Username,
    Number,
    Date,
    Totp,
    CustomSecret,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Template {
    pub id: String,
    pub name: String,
    pub icon_id: String,
    pub color_id: String,
    pub fields: Vec<TemplateField>,
    pub built_in: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ItemFieldValue {
    pub field_id: String,
    pub value: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Item {
    pub id: String,
    pub template_id: String,
    pub title: String,
    pub category: String,
    pub color_id: String,
    pub values: Vec<ItemFieldValue>,
    pub modified_at_ms: i64,
}

pub fn built_in_templates() -> Vec<Template> {
    vec![
        template(
            "tpl_password",
            "Пароль",
            "key",
            "blue",
            vec![
                field("username", "Логин", FieldType::Username, false, false),
                field("password", "Пароль", FieldType::Password, true, true),
                field("url", "Сайт", FieldType::Url, false, false),
                field("notes", "Заметки", FieldType::MultilineNote, false, false),
            ],
        ),
        template(
            "tpl_payment_card",
            "Банковская карта",
            "card",
            "teal",
            vec![
                field("holder", "Владелец карты", FieldType::Text, false, false),
                field(
                    "number",
                    "Номер карты",
                    FieldType::CustomSecret,
                    true,
                    false,
                ),
                field("expires", "Действует до", FieldType::Date, false, false),
                field("cvv", "CVV", FieldType::Password, false, true),
            ],
        ),
        template(
            "tpl_identity",
            "Документ",
            "id",
            "violet",
            vec![
                field("full_name", "ФИО", FieldType::Text, true, false),
                field(
                    "document_number",
                    "Номер документа",
                    FieldType::CustomSecret,
                    true,
                    false,
                ),
                field("issued_at", "Дата выдачи", FieldType::Date, false, false),
            ],
        ),
        template(
            "tpl_bank_account",
            "Банковский счет",
            "bank",
            "blue",
            vec![
                field("bank", "Банк", FieldType::Text, true, false),
                field(
                    "account",
                    "Номер счета",
                    FieldType::CustomSecret,
                    true,
                    false,
                ),
                field(
                    "login",
                    "Логин интернет-банка",
                    FieldType::Username,
                    false,
                    false,
                ),
                field(
                    "password",
                    "Пароль интернет-банка",
                    FieldType::Password,
                    false,
                    true,
                ),
            ],
        ),
    ]
}

fn template(
    id: &str,
    name: &str,
    icon_id: &str,
    color_id: &str,
    fields: Vec<TemplateField>,
) -> Template {
    Template {
        id: id.to_owned(),
        name: name.to_owned(),
        icon_id: icon_id.to_owned(),
        color_id: color_id.to_owned(),
        fields,
        built_in: true,
    }
}

fn field(
    id: &str,
    label: &str,
    field_type: FieldType,
    required: bool,
    secret: bool,
) -> TemplateField {
    TemplateField {
        id: id.to_owned(),
        label: label.to_owned(),
        field_type,
        required,
        secret,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn built_in_card_hides_only_cvv() {
        let card = built_in_templates()
            .into_iter()
            .find(|template| template.id == "tpl_payment_card")
            .expect("payment card template");
        let secret_fields: Vec<_> = card
            .fields
            .iter()
            .filter(|field| field.secret)
            .map(|field| field.id.as_str())
            .collect();
        assert_eq!(secret_fields, vec!["cvv"]);
    }

    #[test]
    fn bank_account_number_is_visible_but_password_is_secret() {
        let account = built_in_templates()
            .into_iter()
            .find(|template| template.id == "tpl_bank_account")
            .expect("bank account template");
        let number = account
            .fields
            .iter()
            .find(|field| field.id == "account")
            .expect("account field");
        let password = account
            .fields
            .iter()
            .find(|field| field.id == "password")
            .expect("password field");
        assert!(!number.secret);
        assert!(password.secret);
    }
}
