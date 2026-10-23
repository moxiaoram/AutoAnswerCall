# Status · ClashAssist 0.4.0

Implemented: removed synthetic simulator; 8192-entry serialized hook timeline; session isolation; 300-second capture; periodic disk checkpoints; structured rolling JSONL journal; full JSON export; confirmed-state single-battle scheduler and explicit backend registration contract; exact build gate; timeout/error stop behavior; offline analyzer and regression tests.

Missing: concrete verified game backend implementing search / deployment / ending / world-state reads. No real automated battle can run from this repository alone.

Unverified: iOS compilation, package generation, on-device injection/UI, existing candidate Hook signatures, target-game compatibility, actual game actions. Candidate offsets and raw argument words must not be treated as verified callable APIs.
