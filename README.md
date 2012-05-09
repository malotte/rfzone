tellstick
=====

tellstick is an erlang application that enables remote control handling from 
an iPhone/iPod/iPhone app.

To use tellstick you need:
<ul>
<li>A tellstick usb pin, see www.telldus.com. </li>
<li>A computer running Linux or MacOS (Windows will be available later).</li>
<li>An iPhone/iPod/iPad with the Seazone RC app, available at App Store.</li>
</ul>

tellstick currently has support for the following remote control protocols:
<ul>
<li>nexa</li>
<li>nexax</li>
<li>waveman</li>
<li>sartano</li>
<li>ikea</li>
<li>risingsun</li>
</ul>

### Dependencies

To build tellstick you will need a working installation of Erlang R15B (or
later).<br/>
Information on building and installing [Erlang/OTP](http://www.erlang.org)
can be found [here](https://github.com/erlang/otp/wiki/Installation)
([more info](https://github.com/erlang/otp/blob/master/INSTALL.md)).

tellstick is built using rebar that can be found [here](https://github.com/basho/rebar), with building instructions [here](https://github.com/basho/rebar/wiki/Building-rebar).

tellstick also requires the following applications to be installed:
<ul>
<li>sl - https://github.com/tonyrog/sl</li>
<li>eapi - https://github.com/tonyrog/eapi</li>
<li>can - https://github.com/tonyrog/can</li>
<li>canopen - https://github.com/tonyrog/canopen</li>
</ul>

To use the tellstick usb pin you need the correct driver installed.
So far it has been an FTDI driver that can be found at www.ftdichip.com, to be sure it might be advisable to check on www.telldus.com.

### Downloading

Clone the repository in a suitable location:

```sh
$ git clone git://github.com/malotte/tellstick.git
```
### Configurating
#### Concepts

tellstick and SeaZone RC are communicating using CANOpen over UDP. This means they are addressed by CANOpen node ids. See www.canopensolutions.com for a description of CANOpen. 

In this case the SeaZone RC app is broadcasting messages that are handled by canopen/tellstick after which a reply is sent. For this to work tellstick must be configured to know that the broadcasted messages should be handled by it.

In the SeaZone RC app you can configure the "RemoteId". According to the standard node ids can either be short(11 bits) or extended(27 bits). The SeaZone RC app is configured to use extended node ids.<br/>
This id should then be included in the tellstick configuration file described below.

In the SeaZone app you must define devices corresponding to the real devices you want to control. Devices can be grouped and also added to panels to get a better overview. The device channel given to a device must correspond to the remote channel configured in tellstick.conf.

#### Files

Arguments to all applicable erlang applications are specified in an erlang configuration file.<br/>
An example can be found in ["sys.config"](https://github.com/malotte/tellstick/raw/master/sys.config).<br/>

tellstick uses a config file where the devices to control are specified, the syntax is explained in the file. A description is also available in [User's Guide - How to configure tellstick](https://github.com/malotte/tellstick/wiki/howto_configure_tellstick).<br/>
The device for the tellstick usb pin is also specified in this file. <br/>

Default file is ["tellstick/priv/tellstick.conf"](https://github.com/malotte/tellstick/raw/master/priv/tellstick.conf).<br/>
Either update this file or create a new at any location and specify that in sys.config.

### Building

Rebar will compile all needed dependencies.<br/>
Compile:

```sh
$ cd tellstick
$ rebar compile
...
==> tellstick (compile)
```

### Running

There is a quick way to run the application for testing:

```sh
$ erl -config sys -pa <path>/tellstick/ebin
>tellstick:start().
```
(Instead of specifing the path to the ebin directory you can set the environment ERL_LIBS.)

It is possible to change configuration file using:

```sh
>tellstick_srv:reload(<File>).
```

Stop:

```sh
>halt().
```

### Release

To generate a proper release follow the instructions in 
https://github.com/basho/rebar/wiki/Release-handling.

You have to update the file "tellstick/rel/files/sys.config" with your own settings <b> before </b> the last step, 
```
$ rebar generate
```
.

When generating a new release the old has to be (re)moved.

Start node:

```sh
$ cd rel
$ tellstick/bin/tellstick start
```

(If you want to have access to the erlang node use 
``` 
console 
```
instead of 
``` 
start
```
.)

### Documentation

tellstick is documented using edoc. To generate the documentation do:

```sh
$ cd tellstick
$ rebar doc
```
