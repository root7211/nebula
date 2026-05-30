#!/usr/bin/env python3
"""
smoke_phase5_5_unified_main.py
Phase 5.5: nebula_main unified declaration mode — Smoke Test

Verifies:
  1. nebula_main accepts components/states/bindings/events and auto-delegates to nebula_app
  2. counter_unified_demo.nelua structural correctness
  3. nebula_apps.nelua delegation logic exists
  4. Equivalence with counter_demo.nelua (separate mode)
  5. Documentation comments updated
"""
import re, sys, os

pass_count = 0
fail_count = 0

def check(name, cond):
    global pass_count, fail_count
    if cond:
        pass_count += 1
    else:
        fail_count += 1
        print(f"[FAIL] {name}")

script_dir = os.path.dirname(os.path.abspath(__file__))
src_dir = os.path.join(script_dir, "..", "src")
examples_dir = os.path.join(script_dir, "..", "examples")

def read_file(path):
    with open(path, "r") as f:
        return f.read()

unified_demo = read_file(os.path.join(examples_dir, "counter_unified_demo.nelua"))
counter_demo = read_file(os.path.join(examples_dir, "counter_demo.nelua"))
apps_src = read_file(os.path.join(src_dir, "nebula_apps.nelua"))

# =============================================================================
# Test Group 1: counter_unified_demo.nelua — structural correctness
# =============================================================================
check("1.1_uses_require_nebula", 'require "nebula"' in unified_demo)
check("1.2_uses_nebula_visual", "nebula_visual" in unified_demo)
check("1.3_uses_nebula_main", "nebula_main" in unified_demo)

# Key: unified mode should NOT have a separate nebula_app call (exclude comments)
unified_code_lines = [l for l in unified_demo.splitlines() if not l.strip().startswith("--")]
unified_code = "\n".join(unified_code_lines)
check("1.4_no_separate_nebula_app", "nebula_app(" not in unified_code)
check("1.5_no_app_begin", "nebula_app_begin" not in unified_demo)
check("1.6_no_app_end", "nebula_app_end" not in unified_demo)
check("1.7_no_derive_app", "nebula_derive_app" not in unified_demo)

# states/bindings/events directly in nebula_main opts
check("1.8_has_components_in_main", re.search(r"components\s*=", unified_demo) is not None)
check("1.9_has_states_in_main", re.search(r"states\s*=", unified_demo) is not None)
check("1.10_has_bindings_in_main", re.search(r"bindings\s*=", unified_demo) is not None)
check("1.11_has_events_in_main", re.search(r"events\s*=", unified_demo) is not None)
check("1.12_has_on_init", "on_init" in unified_demo)
check("1.13_has_on_frame", "on_frame" in unified_demo)
check("1.14_has_title", re.search(r"title\s*=", unified_demo) is not None)
check("1.15_state_count", 'name = "count"' in unified_demo)
check("1.16_binding_doubled", 'target = "doubled"' in unified_demo)
check("1.17_event_click", 'event_type = "click"' in unified_demo)
check("1.18_init_themed", "init_themed" in unified_demo)

# =============================================================================
# Test Group 2: nebula_apps.nelua — delegation logic exists
# =============================================================================
check("2.1_main_checks_components", "if opts.components then" in apps_src)
check("2.2_main_calls_nebula_app", "nebula_app(app_type, app_spec)" in apps_src)
check("2.3_main_forwards_states", re.search(r"states\s*=\s*opts\.states", apps_src) is not None)
check("2.4_main_forwards_bindings", re.search(r"bindings\s*=\s*opts\.bindings", apps_src) is not None)
check("2.5_main_forwards_events", re.search(r"events\s*=\s*opts\.events", apps_src) is not None)
check("2.6_main_forwards_components", re.search(r"components\s*=\s*opts\.components", apps_src) is not None)
check("2.7_main_clears_consumed_fields", re.search(r"opts\.components\s*=\s*nil", apps_src) is not None)
check("2.8_main_forwards_slots", re.search(r"slots\s*=\s*opts\.slots", apps_src) is not None)
check("2.9_main_forwards_texts", re.search(r"texts\s*=\s*opts\.texts", apps_src) is not None)
check("2.10_main_forwards_layout", re.search(r"layout\s*=\s*opts\.layout", apps_src) is not None)

# =============================================================================
# Test Group 3: documentation comments
# =============================================================================
check("3.1_has_unified_usage_comment",
      "unified single call" in apps_src or "单调用模式" in apps_src)
check("3.2_has_phase_5_5_tag", "Phase 5.5" in apps_src)

# =============================================================================
# Test Group 4: equivalence with counter_demo.nelua (separate mode)
# =============================================================================
check("4.1_both_have_clickable",
      '"clickable"' in unified_demo and '"clickable"' in counter_demo)
check("4.2_both_have_count_state",
      'name = "count"' in unified_demo and 'name = "count"' in counter_demo)
check("4.3_both_have_doubled_binding",
      'target = "doubled"' in unified_demo and 'target = "doubled"' in counter_demo)
check("4.4_both_have_click_event",
      'event_type = "click"' in unified_demo and 'event_type = "click"' in counter_demo)
check("4.5_both_have_same_mutation",
      "self.count = self.count + 1" in unified_demo and
      "self.count = self.count + 1" in counter_demo)
check("4.6_both_have_same_compute",
      "self.doubled = self.count * 2" in unified_demo and
      "self.doubled = self.count * 2" in counter_demo)

unified_lines = unified_demo.count("\n")
separate_lines = counter_demo.count("\n")
check("4.7_unified_not_longer_than_separate", unified_lines <= separate_lines)

# =============================================================================
# Test Group 5: backward compat — separate mode unaffected
# =============================================================================
check("5.1_separate_mode_has_nebula_app", "nebula_app(" in counter_demo)
check("5.2_separate_mode_has_nebula_main", "nebula_main(" in counter_demo)
check("5.3_separate_mode_components_in_app", 'nebula_app("CounterApp"' in counter_demo)

# =============================================================================
# Summary
# =============================================================================
total = pass_count + fail_count
print(f"smoke_phase5_5_unified_main: {pass_count}/{total} passed")
if fail_count > 0:
    print(f"  unified: {unified_lines} lines, separate: {separate_lines} lines")
    sys.exit(1)
else:
    print(f"  unified: {unified_lines} lines, separate: {separate_lines} lines (-{separate_lines - unified_lines} lines)")
