#
# Make the rfZone test modules
#

MODULES = \
	rfzone_node \
	rfzone_test_lib \
	rfzone_SUITE \
	rfzone_http_server \
	rfzone_customer_server \
	rfzdemo \
	rfzdemo_index \
	rfzdemo_inets \
	rfzdemo_deps \
	rfzone_exo_SUITE


EBIN = .
ERLC = erlc

ERLDIR  := $(shell erl -noshell -eval "io:format([126,115,126,110],[code:root_dir()])" -s erlang halt)

override ERLC_FLAGS = -Wall -I ../include -I .

debug: ERLC_FLAGS += +debug_info -Ddebug

OBJS = $(MODULES:%=$(EBIN)/%.beam)

all: $(OBJS)

debug: all

clean:
	rm -f $(OBJS) 

test:
	$(ERLDIR)/bin/ct_run -include ../include -suite tellstick_SUITE

-include depend.mk

./%.beam:	%.erl
	erlc  $(ERLC_FLAGS) $<
