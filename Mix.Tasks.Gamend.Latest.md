# `mix gamend.latest`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/mix/tasks/gamend.latest.ex#L1)

Sets `@gamend_min` in the app's `mix.exs` to Gamend's newest release on Hex.

    mix gamend.latest

An app's lock holds no Gamend entry, and Docker keeps its `mix deps.get`
layer until `mix.exs` or `mix.lock` changes, which a release does not do. So
a deploy goes on building the release that layer first resolved. Run from an
app's `precommit`, this moves `mix.exs`, and the build that commit reaches
takes the release.

It only raises. With Hex out of reach it warns and changes nothing, so a
commit can be prepared offline.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
