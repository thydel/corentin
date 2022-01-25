#!/usr/bin/env -S make -Orecurse --no-print-directory -f

MAKEFLAGS += -Rr --warn-undefined-variables
SHELL != which bash
.SHELLFLAGS := -euo pipefail -c

.ONESHELL:
.DELETE_ON_ERROR:
.PHONY: phony
.DEFAULT_GOAL := main

self := $(lastword $(MAKEFILE_LIST))
$(self):;

tmp := tmp
out := $(tmp)/out
lock := $(tmp)/$(self).lock
next := $(tmp)/host
rand := $(tmp)/rand
stone := $(tmp)/stone

hosts := tst2 tst4 tst5 tst6 tst8

# Generate rotational sequence of host from $(host) with index in file $(next)
host: $(next); @ n=$$(cat $<); echo $(hosts) | fmt -1 | sed -n $${n}p; echo "$$n % $(words $(hosts)) + 1" | bc -q | sponge $<
$(next): | $(tmp); @ echo 1 > $@
$(tmp):; @ mkdir -p $@

# Lock protect concurrent acces to host sequence generator
host := flock $(lock) $(self) host

# The pseudo task we distribute on $(hosts) nodes
fib := fib () { echo -n $${1:?} $$(date +%s) $$(hostname) $${2:?} ""; echo "define fib (n) { if (n <= 2) return 1; return fib(n - 1) + fib(n - 2) }; fib($${2:?})" | bc -ql; }

# Generate constant random sequence
nfibs ?= 99			# Generate this many fibs
mfib ?= 33			# Max fib arg value
fibs != seq -w $(nfibs)		# Sequence index
$(rand): | $(tmp); @ (RANDOM=42; for i in $(fibs); do echo $$RANDOM % $(mfib); done) | bc > $@
rand: phony $(rand)

# Drive the concurrent call to fib on all remote nodes
$(out)/%: $(rand) $(stone) | $(out); +@ $(fib); { declare -f fib; echo fib $(@F) $$(sed -n $(@F)p $<); } | ssh $$($(host)).admin2 bash >> $@; tail -1 $@
$(out):; @ mkdir -p $@
$(stone): | $(tmp); @ touch $@

sponge := /usr/bin/sponge
$(sponge):; $(error sudo apt install moreutils)

main: phony $(sponge) $(fibs:%=$(out)/%)
clean: phony; @ rm -rf $(tmp)
stone: phony | $(tmp); @ touch $(stone)

################

~ := run
$~: $~ := $(self) clean;
$~: $~ += time $(self);
$~: $~ += $(self) stone;
$~: $~ += time $(self) -j10;
$~:; $($@)

~ := $(tmp)/seq $(tmp)/par
$~: seq := NR%2
$~: par := NR%2==0
$~: $(tmp)/% : $(sort $(wildcard $(out)/*)); awk '$($*)' $^ > $@
seqpar: $~

~ := compare-fib
$~: awk := awk '{ print $$1, $$4, $$5 }'
$~: $~ := diff <($(awk) $(tmp)/seq) <($(awk) $(tmp)/par)
$~:; $($@)

~ := compare-node
$~: awk := awk '{ print $$3 }'
$~: $~ := diff <($(awk) $(tmp)/seq | sort) <($(awk) $(tmp)/par | sort)
$~:; $($@)
