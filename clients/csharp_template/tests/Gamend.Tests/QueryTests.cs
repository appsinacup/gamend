using Newtonsoft.Json.Linq;
using Xunit;
using static Gamend.Tests.Wire;

namespace Gamend.Tests
{
    public class QueryTests
    {
        [Fact]
        public void EscapeLeavesTheUnreservedSetAloneAndEncodesTheRest()
        {
            Assert.Equal("AZaz09-_.~", Query.Escape("AZaz09-_.~"));
            Assert.Equal("a%20b%26c%3Dd%2Fe%3Ff%23g%2Bh", Query.Escape("a b&c=d/e?f#g+h"));
            Assert.Equal("%C3%A9", Query.Escape("é"));
            Assert.Equal("", Query.Escape(""));
        }

        [Fact]
        public void GivenIsAKeyWithAValueNeverNullNeverOnANonObject()
        {
            var table = J("{'a': 1, 'b': null, 'c': ''}");
            Assert.True(Query.Given(table, "a"));
            Assert.False(Query.Given(table, "b"));
            Assert.True(Query.Given(table, "c"));
            Assert.False(Query.Given(table, "d"));
            Assert.False(Query.Given(JValue.CreateNull(), "a"));
            Assert.False(Query.Given(null, "a"));
            Assert.False(Query.Given(J("[1]"), "a"));
        }

        [Fact]
        public void QueryKeepsTheDeclaredOrderAndSkipsWhatIsNotGiven()
        {
            var options = J("{'page': 2, 'title': 'a b', 'is_hidden': false, 'min_users': null, 'unknown': 'x'}");
            Assert.Equal("?title=a%20b&is_hidden=false&page=2", Query.Build(options, "title", "is_hidden", "min_users", "page", "page_size"));
            Assert.Equal("", Query.Build(new JObject(), "page"));
            Assert.Equal("", Query.Build(null, "page"));
            Assert.Equal("?ratio=1.5", Query.Build(J("{'ratio': 1.5}"), "ratio"));
        }
    }
}
