# `Gamend.Lock.Local`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/lock/local.ex#L1)

Reentrant, cluster-wide keyed mutex — the non-Postgres half of
`Gamend.Lock.serialize/3`.

`:global` shares a lock between holders with the same *requester*, so the
resource goes in the resource slot and `self()` in the requester slot. Putting
the protected id in the requester slot lets two concurrent requests for it
both acquire — the exact case the lock exists to prevent.

`self()` also makes it reentrant, which core needs: the matchmaking sweep
takes a lock and then creates a match, which takes one again. `:global`
releases on process death.

# `trans`

```elixir
@spec trans(term(), (-&gt; result)) :: result when result: term()
```

Runs `fun` holding the lock for `key`. Blocks; reentrant within a process.

# `trans_on_node`

```elixir
@spec trans_on_node(term(), (-&gt; result)) :: result when result: term()
```

As `trans/2`, on this node only. On Postgres the advisory lock is the
cluster-wide one; this queues a node's own callers in the BEAM, where waiting
is free, instead of each holding a pooled connection blocked on the database.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
