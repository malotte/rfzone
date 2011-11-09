#
# Make the pds proto
#
ERLC = erlc

ERL_FLAGS = -Wall 
DIA_FLAGS =

MODULES = \
	tellstick_drv \
	tellstick 

EBIN = ../ebin

override ERLC_FLAGS += $(ERL_FLAGS)

debug: ERLC_FLAGS += +debug_info -Ddebug -W

OBJS = $(MODULES:%=$(EBIN)/%.beam)

all: $(OBJS)

debug: all

depend:
	edep -MM -o ../ebin $(ERLC_FLAGS) $(MODULES:%=%.erl) > depend.mk

dialyze:
	dialyzer --src -o dia.out $(DIA_FLAGS) -c $(MODULES:%=%.erl) 

edoc:
	erl -noshell -pa doc -run edoc_run application "tellstick" '".."' '[{private,false},no_packages,{sort_functions,false}]'

clean:
	rm -f $(OBJS) 

-include depend.mk

../ebin/%.beam:	%.erl
	erlc -o ../ebin $(ERLC_FLAGS) $<
