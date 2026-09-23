# 31: Copy, Save, and drag from the editor

**What to build:** Copy, Save, or dragging from the editor finalizes the flattened result and delivers exactly what Prateek sees.

**Blocked by:** 11, 12, 26

**Status:** ready-for-agent

- [ ] Each action finalizes the rendered revision through the shared finalization policy, then delivers it.
- [ ] Delivery failure leaves the commit intact and can be retried on the same revision.
- [ ] Canary cases on the saved file and the dragged file.

## Comments
