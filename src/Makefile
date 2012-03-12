#
# Make the tellstick application
#
MODULES = \
	tellstick \
	tellstick_sup \
	tellstick_srv \
	tellstick_drv \
	tellstick_node


ERLC = erlc
EBIN = ../ebin

ERL_FLAGS = -Wall 

override ERLC_FLAGS += $(ERL_FLAGS)

debug: ERLC_FLAGS += +debug_info -Ddebug

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
