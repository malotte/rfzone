#
# Make the rfZone test modules
#

MODULES = \
	rfzone_node \
	rfzone_SUITE \
	rfzone_http_server \
	rfzone_customer_server \
	rfzone_exo_SUITE


EBIN = .
ERLC = erlc

ERLDIR  := $(shell erl -noshell -eval "io:format([126,115,126,110],[code:root_dir()])" -s erlang halt)

override ERLC_FLAGS = -Wall -I ../include 

debug: ERLC_FLAGS += +debug_info -Ddebug

OBJS = $(MODULES:%=$(EBIN)/%.beam)

all: $(OBJS)

debug: all

depend:
	edep -MM -o ../ebin $(ERLC_FLAGS) $(MODULES:%=%.erl) > depend.mk

dialyze:
	dialyzer --src -o dia.out -I ../include -c $(MODULES:%=%.erl) 

edoc:
	erl -noshell -pa doc -run edoc_run application "canopen" '".."' '[{private,false},no_packages,{sort_functions,false}]'

clean:
	rm -f $(OBJS) 

test:
	$(ERLDIR)/bin/ct_run -include ../include -suite tellstivk_SUITE

-include depend.mk

./%.beam:	%.erl
	erlc -o ../ebin $(ERLC_FLAGS) $<
