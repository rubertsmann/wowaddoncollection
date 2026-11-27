# Mail probe run 1 (2026-11-27, 1.4.3-dev, user)

User ran `api` (mailbox closed) and the mailbox steps with a /reload after each; only the last run survived (the probe
kept one run; fixed afterwards). The surviving `burst 2589 2 2840 1` report:

```
[ 0.00] --- burst (1.4.3-dev, 2026-11-27 11:08:55) ---
[ 0.00] item 2589: not in the bags (or every stack locked)
[ 0.00] item 2840: not in the bags (or every stack locked)
[ 0.00] attachments now: 1: Linen Cloth, 2589, 132889, 20, 1 | 2: (nothing) | ... | 12: (nothing)
[ 0.00] done. Check the Send Mail tab. Nothing was sent; closing the mailbox returns the attachments.
```

Read from it:
- `GetSendMailItem(i)` works: name, itemID, texture, count, quality.
- An attachment (Linen Cloth x20, a whole stack) made by an earlier step was still in the draft after `/reload`.
- Whether the earlier `attach 2589 3` split the stack (3) or attached all 20 is unknown (report lost).
