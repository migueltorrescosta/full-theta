.PHONY: gate

# make gate [TIERS="l0 l1"]  (default: ci)
gate:
	tools/gate.sh $(TIERS)
