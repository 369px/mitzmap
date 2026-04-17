# MITZMAP Chess Engine v1.0

**MITZMAP** is a high-performance chess engine designed specifically for the **Picotron** fantasy workstation. It combines classical search techniques with modern optimizations to deliver a "Master" level experience within a restricted environment.

## The Name: MITZMAP 🔍
The name is an acronym for the core algorithms and techniques that power the engine's "brain":

- **M**op-up: Dedicated endgame heuristics to drive the opponent's king to the edge and secure checkmate.
- **I**terative Deepening: A search technique that explores the move tree at increasing depths to optimize time management.
- **T**ransposition Table: A high-performance cache (Zobrist-based) that stores previously evaluated positions to avoid redundant calculations.
- **Z**obrist Hashing: An incremental hashing system that uniquely identifies board states for lightning-fast memory lookups.
- **M**inimax: The foundational decision-making algorithm used to navigate the chess game tree.
- **A**lpha-beta pruning: An optimization of Minimax that "prunes" away branches that cannot possibly influence the final decision.
- **P**iece-Square Tables (PST): Positional evaluation matrices that guide pieces toward their most effective squares.

## Features
- **Incremental Zobrist Hashing**: Synchronized with move generation for maximum efficiency.
- **Stalemate Contempt**: An intelligent evaluation logic that prevents accidental draws when holding a significant material advantage.
- **Quiet Search (Quiescence)**: Handles tactical "explosions" to avoid the horizon effect.
- **Opening Book**: A curated list of manual moves (e4, d4, c4, etc.) for a professional opening phase.
- **Early Exit optimization**: Detects checkmate or overwhelming wins early to save computation time.

## Directory Structure 📂
```text
Mitzmap/
├── LICENSE             # MIT License
├── README.md           # This file
└── src/
    ├── core/           # Board logic, rules, and history
    ├── engine/         # Search, evaluation, and search optimizations
    └── data/           # Constants and opening book
```

## How to use in Picotron
To integrate MITZMAP into your own project, copy the `src` folder into your cart and initialize the engine via `ai_start_thinking(color, board, difficulty)`.

## License
This project is licensed under the **MIT License** - see the LICENSE file for details.

---
*Created by 369px*
