use gamend::detail::{escape, given, query};
use gamend::{json, Value};

#[test]
fn escape_leaves_the_unreserved_set_alone_and_encodes_the_rest() {
    assert_eq!(escape("AZaz09-_.~"), "AZaz09-_.~");
    assert_eq!(escape("a b&c=d/e?f#g+h"), "a%20b%26c%3Dd%2Fe%3Ff%23g%2Bh");
    assert_eq!(escape("é"), "%C3%A9");
    assert_eq!(escape(""), "");
}

#[test]
fn given_means_a_key_with_a_value_never_null_never_on_a_non_object() {
    let table = json!({ "a": 1, "b": null, "c": "" });
    assert!(given(&table, "a"));
    assert!(!given(&table, "b"));
    assert!(given(&table, "c"));
    assert!(!given(&table, "d"));
    assert!(!given(&Value::Null, "a"));
    assert!(!given(&json!([1]), "a"));
}

#[test]
fn query_keeps_the_declared_order_and_skips_what_is_not_given() {
    let options = json!({ "page": 2, "title": "a b", "is_hidden": false, "min_users": null,
                          "unknown": "x" });
    assert_eq!(
        query(
            &options,
            &["title", "is_hidden", "min_users", "page", "page_size"]
        ),
        "?title=a%20b&is_hidden=false&page=2"
    );
    assert_eq!(query(&json!({}), &["page"]), "");
    assert_eq!(query(&Value::Null, &["page"]), "");
    assert_eq!(query(&json!({ "ratio": 1.5 }), &["ratio"]), "?ratio=1.5");
}
