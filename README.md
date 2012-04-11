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

### Dependencies

To build tellstick you will need a working installation of Erlang R15B (or
later).

tellstick also requires the following applications to be installed:
<ul>
<li>sl - https://github.com/tonyrog/sl</li>
<li>eapi - https://github.com/tonyrog/eapi</li>
<li>can - https://github.com/tonyrog/can</li>
<li>canopen - https://github.com/tonyrog/canopen</li>
</ul>


#### Downloading

Clone the repository:

```sh
$ git clone git://github.com/malotte/tellstick.git
```
#### Configurating

tellstick uses a config file where the devices to control are specified.<br/>
Default file is ["tellstick/priv/tellstick.conf"](https://github.com/malotte/tellstick/blob/master/priv/tellstick.conf).<br/>
Arguments to the erlang applications are specified in "tellstick/rel/files/sys.config" that is created by rebar create_node and should be configured before rebar generate. An example can be found in ["sys.config"](https://github.com/malotte/tellstick/blob/master/sys.config).<br/>

#### Building using rebar

Compile:<br/>
```sh
$ cd tellstick
$ rebar compile
Recompile: src/
...
Recompile: src/
==> tellstick (compile)
```

First time you need to create a node setup.<br/>
```sh
$ rebar create-node
....
```
Then you have to update the file"tellstick/rel/files/sys.config" as described above.

Generate release:<br/>
```sh
$ cd rel
$ rebar generate
....
```

Start node:<br/>
```sh
$ cd rel
$ tellstick/bin/tellstick 
....
```

You can also package the release and move it as you please using for example OTP's sys_tool.