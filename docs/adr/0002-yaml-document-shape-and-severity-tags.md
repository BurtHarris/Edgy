# YAML Sequence Shape And Severity Tags

The canonical WhyLog output is YAML text with a top-level ordered sequence. Entries can be untagged narrative items or tagged signal items using !i, !w, and !e, with minimal quoting and insertion-order fidelity, because severity tags are the core semantic contract while structure remains intentionally lightweight.