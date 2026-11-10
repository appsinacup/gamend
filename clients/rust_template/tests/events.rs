use gamend::events;

#[test]
fn a_socket_message_is_named_by_its_channel_and_event() {
    assert_eq!(events::channel_of("lobby:12"), "lobby");
    assert_eq!(events::channel_of("lobbies"), "lobbies");
    assert_eq!(
        events::signal_of("lobby:12", "updated"),
        events::LOBBY_UPDATED
    );
    assert_eq!(
        events::signal_of("user:u1", "updated"),
        events::USER_UPDATED
    );
    assert_eq!(
        events::signal_of("lobby:l1", "user_joined"),
        events::LOBBY_MEMBER_JOINED
    );
    assert_eq!(
        events::signal_of("lobby:l1", "no_such_event"),
        events::MESSAGE
    );
    assert_eq!(events::signal_of("nowhere:1", "updated"), events::MESSAGE);
}

#[test]
fn every_row_names_a_signal() {
    for row in events::TABLE {
        assert!(!row.channel.is_empty());
        assert!(!row.event.is_empty());
        assert!(!row.signal.is_empty());
    }
}
