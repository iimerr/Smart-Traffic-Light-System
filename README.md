# Smart Traffic Light Controller with Adaptive Timing and Emergency Vehicle Priority 🚦

> EFB4133: Digital Systems Design — Mini Project Report
> Semester: May 2026 |
> Universiti Teknologi PETRONAS

## Overview

A Verilog RTL implementation of a traffic light controller for a 2-approach junction (North–South and East–West), built as a Moore finite state machine with two behavioural upgrades over a basic fixed-time controller:

- **Vehicle-actuated adaptive timing** — each approach has a sensor reporting vehicle density; green duration is extended within a `MIN_GREEN`/`MAX_GREEN` bound.
- **Emergency vehicle preemption** — an approach can request emergency priority, which safely clears the junction (all-red) and grants a fixed emergency green, then resumes the normal cycle. Simultaneous NS+EW emergency requests are handled fairly via alternating tie-break arbitration — neither direction is starved and no request is dropped.

The one rule that can never be broken: **NS and EW must never show green at the same time.**

## Functional Requirements

- **FR1** — Cycle NS/EW phase groups through GREEN, YELLOW, ALL-RED safely; NS and EW never both green.
- **FR2** — Each approach has a vehicle density sensor; green duration extends proportionally, bounded by `MIN_GREEN`/`MAX_GREEN`.
- **FR3** — Each approach has an emergency request input; asserting it preempts the current phase through a safe all-red clearance and grants a fixed emergency green, then resumes the normal cycle.
- **FR4** — If both approaches request emergency priority in the same cycle, both are served one after another with a fair tie-break so neither direction is starved.
- **FR5** — Every module has a self-checking testbench, plus one full top-level integration testbench.

## Design Requirements

- Single clock, active-low asynchronous reset, Moore-style registered outputs.
- Parameterised timing (`MIN_GREEN`, `MAX_GREEN`, `YELLOW_T`, `ALLRED_T`, `EMG_GREEN`) so the same RTL works for simulation or real deployment.
- Separate `sensor`, `timer`, `emergency`, and `FSM` modules tied together in one top module.

## System Specification

Light encoding (`ns_light` / `ew_light`, 2 bits): `00` = RED, `01` = YELLOW, `10` = GREEN.

**Timing parameters (simulation scale, in cycles):**

| Parameter | Value | Meaning |
|---|---|---|
| `MIN_GREEN` | 5 | Shortest green (density = 0) |
| `MAX_GREEN` | 12 | Longest green regardless of density |
| `YELLOW_T` | 2 | Yellow duration |
| `ALLRED_T` | 2 | All-red clearance between phases |
| `EMG_GREEN` | 6 | Fixed green given to an emergency vehicle |

Adaptive green formula: `green_cycles = min(MIN_GREEN + density, MAX_GREEN)`, where `density` is the saturating 0–15 vehicle count from that approach's `sensor_unit`.

## Architecture

```
traffic_light_top
├── sensor_unit (NS)      — vehicle_pulse -> density[3:0]
├── sensor_unit (EW)      — vehicle_pulse -> density[3:0]
├── emergency_unit        — arbitrates ns/ew emergency requests, fair tie-break
└── traffic_fsm           — 11-state Moore FSM (owns internal timer_unit)
        -> ns_light[1:0], ew_light[1:0]
```

### Modules

| Module | Purpose |
|---|---|
| `sensor_unit.v` | Models a vehicle detector for one approach; counts `vehicle_pulse` into a saturating 4-bit density register, cleared by the FSM after use |
| `timer_unit.v` | Reusable parameterised down-counter; the FSM loads a duration and polls `done`; used for every phase (green/yellow/all-red/emergency) |
| `emergency_unit.v` | Latches NS/EW emergency requests so short pulses aren't lost while busy; arbitrates simultaneous requests via an alternating `last_served` fairness flag |
| `traffic_fsm.v` | Core 11-state Moore FSM: normal NS/EW cycle with adaptive green timing, plus emergency preemption via all-red clearance states |
| `traffic_light_top.v` | Top-level integration: 2× `sensor_unit`, `emergency_unit`, `traffic_fsm` |

### FSM States

| Value | State | NS light | EW light |
|---|---|---|---|
| 0 | `S_RESET` | RED | RED |
| 1 | `S_NS_GREEN` | GREEN | RED |
| 2 | `S_NS_YELLOW` | YELLOW | RED |
| 3 | `S_ALLRED_A` | RED | RED |
| 4 | `S_EW_GREEN` | RED | GREEN |
| 5 | `S_EW_YELLOW` | RED | YELLOW |
| 6 | `S_ALLRED_B` | RED | RED |
| 7 | `S_ALLRED_E` (pre-emergency clearance) | RED | RED |
| 8 | `S_EMG_NS` | GREEN | RED |
| 9 | `S_EMG_EW` | RED | GREEN |
| 10 | `S_ALLRED_R` (post-emergency clearance) | RED | RED |

All-red clearance is inserted both before and after every emergency phase, so NS and EW can never be green at the same time — even during a preemption.

## Testing

Each module has a self-checking testbench (PASS/FAIL per check) plus one full-system integration testbench. All testbenches were run with **Icarus Verilog** (`iverilog` / `vvp`) and again on **EDA Playground** (EPWave viewer) for waveform captures.

| Testbench | Verifies |
|---|---|
| `tb_sensor_unit.v` | Density increments per pulse while sampling, saturates at max, clears correctly |
| `tb_timer_unit.v` | Correct load/count-down/`done` pulse behaviour, including mid-run reload |
| `tb_emergency_unit.v` | Single-direction requests served immediately; queued request served right after; simultaneous NS+EW requests arbitrated fairly |
| `tb_traffic_fsm.v` | Adaptive green scales with density and caps at `MAX_GREEN`; safe phase sequencing; emergency preemption via all-red |
| `tb_traffic_light_top.v` | Full-system integration: density build-up, adaptive timing, and simultaneous NS+EW emergency handling with zero safety violations |

**Result:** all five testbenches report `errors = 0` / all checks PASS — including the additional-task scenario of two simultaneous emergency requests, where NS and EW were confirmed to never be green together throughout the entire hand-off.

### Running the tests

```bash
# from the folder containing the .v source and tb_*.v files
iverilog -o sim_sensor sensor_unit.v tb_sensor_unit.v && vvp sim_sensor
iverilog -o sim_timer timer_unit.v tb_timer_unit.v && vvp sim_timer
iverilog -o sim_emergency emergency_unit.v tb_emergency_unit.v && vvp sim_emergency
iverilog -o sim_fsm timer_unit.v traffic_fsm.v tb_traffic_fsm.v && vvp sim_fsm
iverilog -o sim_top sensor_unit.v timer_unit.v emergency_unit.v traffic_fsm.v traffic_light_top.v tb_traffic_light_top.v && vvp sim_top
```

Each testbench dumps a `.vcd` file that can be opened in GTKWave or uploaded to EDA Playground's EPWave viewer.

## Additional Task: Simultaneous Arrivals at Different Approaches

Two distinct cases are handled differently:

- **Ordinary traffic on both approaches at once** — no conflict to resolve. Each approach has its own independent `sensor_unit` density counter; the FSM still serves NS/EW in the same fixed safe order, and each phase length depends only on that approach's own density.
- **Two emergency vehicles arriving on different approaches in the same cycle** — the junction can't grant both at once, so requests are latched (`ns_pending`/`ew_pending`) and served one after another. A `last_served_ns` fairness flag alternates which side wins the tie-break, so a fixed-priority scheme (which would eventually starve one direction) is avoided. The losing side stays latched and is served immediately once the winner's emergency phase completes.

## Tools Used

- Verilog (IEEE 1364-2005 subset)
- Icarus Verilog (`iverilog` / `vvp`)
- EDA Playground (EPWave waveform viewer)
- Graphviz (FSM and block diagrams)

## Repository Contents

> 🚧 Source code to be added.

```
digital-systems-design-traffic-light/
├── README.md
├── rtl/
│   ├── sensor_unit.v
│   ├── timer_unit.v
│   ├── emergency_unit.v
│   ├── traffic_fsm.v
│   └── traffic_light_top.v
├── tb/
│   ├── tb_sensor_unit.v
│   ├── tb_timer_unit.v
│   ├── tb_emergency_unit.v
│   ├── tb_traffic_fsm.v
│   └── tb_traffic_light_top.v
└── docs/
    └── simulation_log.txt
```

## Roles

| Member | Responsibility |
|---|---|
| Aiman Zakwan | Schedule management, system integration (`traffic_light_top`) |
| Harith Iskandar | FSM design (`traffic_fsm.v`) |
| Emir Azimil | Emergency detection & priority logic (`emergency_unit.v`) |
| Nazil Haziq | Testbenches, simulation, verification |
| All members | Report, diagrams, waveform captures |

## References

1. M. Morris Mano and Michael D. Ciletti, *Digital Design: With an Introduction to the Verilog HDL*, 6th ed., Pearson, 2018.
2. Samir Palnitkar, *Verilog HDL: A Guide to Digital Design and Synthesis*, 2nd ed., Prentice Hall, 2003.
3. [Icarus Verilog documentation](http://iverilog.icarus.com/)
4. [EDA Playground](https://www.edaplayground.com/)
5. Federal Highway Administration, *Traffic Signal Timing Manual*, U.S. Department of Transportation, 2008.
6. NTCIP 1202, Object Definitions for Actuated Traffic Signal Controller (ASC) Units.
7. IEEE Std 1364-2005, IEEE Standard for Verilog Hardware Description Language.

## Authors

- Muhammad Nazil Haziq bin Mohd Nizar — 22004961
- Emir Azimil Akbar bin Mohd Fauzi — 24003510
- Muhammad Harith Iskandar bin Mahathir — 24003426
- Muhammad Aiman Zakwan bin Masri — 24003426
