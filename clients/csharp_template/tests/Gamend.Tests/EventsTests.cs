using Xunit;

namespace Gamend.Tests
{
    public class EventsTests
    {
        [Fact]
        public void TopicNamesItsChannel()
        {
            Assert.Equal("lobby", Events.ChannelOf("lobby:12"));
            Assert.Equal("lobbies", Events.ChannelOf("lobbies"));
        }

        [Fact]
        public void SocketMessageIsNamedByItsChannelAndEvent()
        {
            Assert.Equal(Events.LobbyUpdated, Events.SignalOf("lobby:12", "updated"));
            Assert.Equal(Events.UserUpdated, Events.SignalOf("user:u1", "updated"));
            Assert.Equal(Events.LobbyMemberJoined, Events.SignalOf("lobby:l1", "user_joined"));
            Assert.Equal(Events.Message, Events.SignalOf("lobby:l1", "no_such_event"));
            Assert.Equal(Events.Message, Events.SignalOf("nowhere:1", "updated"));
        }

        [Fact]
        public void EveryRowNamesASignal()
        {
            foreach (var row in Events.Table)
            {
                Assert.NotEqual("", row.Channel);
                Assert.NotEqual("", row.Event);
                Assert.NotEqual("", row.Signal);
            }
        }
    }
}
