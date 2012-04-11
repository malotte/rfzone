tellstick
=====

tellstick is an erlang application that enables remote control handling from 
an iPhone/iPod/iPhone app.

To use tellstick you need:
<ul>
<li>A tellstick usb pin, see www.telldus.com </li>
<li>A computer running Linux or MacOS (Windows will be available later)</li>
<li>An iPhone/iPod/iPad with the Seazone RC app</li>
</ul>

Building
--------

Information on building and installing [Erlang/OTP](http://www.erlang.org)
can be found [here](https://github.com/erlang/otp/wiki/Installation)
([more info](https://github.com/erlang/otp/blob/master/INSTALL.md)).

tellstick is built using rebar that can be found [here](https://github.com/basho/rebar).

tellstick also requires the following applications:
sl
eapi,
can,
canopen

### Dependencies

To build tellstick you will need a working installation of Erlang R15B (or
later).


#### Downloading

Clone the repositories:

```sh
$ git clone git://github.com/tonyrog/canopen.git
```
#### Configurating

tellstick uses a config file where the devices to control are specified.
Default file is "tellstick/priv/tellstick.conf".
Arguments to the erlang applications are specified in "tellstick/rel/files/sys.config".

#### Building using rebar

```sh
$ cd tellstick
$ rebar compile
Recompile: src/
...
Recompile: src/
==> tellstick (compile)

$ cd rel
$ rebar generate
....
```
