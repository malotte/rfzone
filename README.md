rfZone
=====

rfZone is an erlang application that enables remote control handling from 
an iPhone/iPod/iPhone app.

To use rfZone you need:
<ul>
<li>A tellstick usb pin, see www.telldus.com. </li>
<li>A computer running Linux or MacOS (Windows will be available later).</li>
<li>An iPhone/iPod/iPad with the Seazone RC app, available at App Store.</li>
</ul>

rfZone currently has support for the following remote control protocols:
<ul>
<li>nexa</li>
<li>nexax</li>
<li>waveman</li>
<li>sartano</li>
<li>ikea</li>
<li>risingsun</li>
</ul>
For information on what protocol a specific brand uses see [Protocol - Brand Map](https://github.com/malotte/rfzone/wiki/Protocol---Brand-Map).<br/>
### Dependencies

To build rfZone you will need a working installation of Erlang R15B (or
later).<br/>
Information on building and installing [Erlang/OTP](http://www.erlang.org)
can be found [here](https://github.com/erlang/otp/wiki/Installation)
([more info](https://github.com/erlang/otp/blob/master/INSTALL.md)).

rfZone is built using rebar that can be found [here](https://github.com/basho/rebar), with building instructions [here](https://github.com/basho/rebar/wiki/Building-rebar).

rfZone also requires the following applications to be installed:
<ul>
<li>uart - https://github.com/tonyrog/uart</li>
<li>can - https://github.com/tonyrog/can</li>
<li>canopen - https://github.com/tonyrog/canopen</li>
</ul>

To use the tellstick usb pin you need the correct driver installed.
So far it has been an FTDI driver that can be found at www.ftdichip.com, to be sure it might be advisable to check on www.telldus.com.

### Download

Clone the repository in a suitable location:

```sh
$ git clone git://github.com/malotte/rfzone.git
```
### Configuration
#### Concepts

rfZone and SeaZone RC are communicating using CANOpen over UDP. This means they are addressed by CANOpen node ids. See www.canopensolutions.com for a description of CANOpen. 

In this case the SeaZone RC app is broadcasting messages that are handled by canopen/rfZone after which a reply is sent. For this to work rfZone must be configured to know that the broadcasted messages should be handled by it.

In the SeaZone RC app you can configure the "RemoteId". According to the standard node ids can either be short(11 bits) or extended(27 bits). The SeaZone RC app is configured to use extended node ids.<br/>
This id should then be included in the rfZone configuration file described below.

In the SeaZone app you must define devices corresponding to the real devices you want to control. Devices can be grouped and also added to panels to get a better overview. The device channel given to a device must correspond to the remote channel configured in rfzone.conf.

#### Files

Arguments to all applicable erlang applications are specified in an erlang configuration file.<br/>
An example can be found in ["sys.config"](https://github.com/malotte/rfzone/raw/master/sys.config).<br/>

rfzone uses a config file where the devices to control are specified, the syntax is explained in the file. A description is also available in [User's Guide - How to configure rfZone](https://github.com/malotte/rfzone/wiki/howto_configure_rfzone).<br/>
The device for the tellstick usb pin is also specified in this file. <br/>

Default file is ["rfzone/priv/rfzone.conf"](https://github.com/malotte/rfzone/raw/master/priv/rfzone.conf).<br/>
Either update this file or create a new at any location and specify that in sys.config.

### Build

Rebar will compile all needed dependencies.<br/>
Compile:

```sh
$ cd rfzone
$ rebar compile
...
==> rfzone (compile)
```

### Run

There is a quick way to run the application for testing:

```sh
$ erl -config sys -pa <path>/rfzone/ebin
>rfzone:start().
```
(Instead of specifing the path to the ebin directory you can set the environment ERL_LIBS.)

It is possible to change configuration file using:

```sh
>rfzone_srv:reload(<File>).
```

Stop:

```sh
>halt().
```

### Release

To generate a proper release follow the instructions in 
 [Release Handling](https://github.com/basho/rebar/wiki/Release-handling) or look in the [Rebar tutorial](http://www.metabrew.com/article/erlang-rebar-tutorial-generating-releases-upgrades).

<b>Before</b> the last step you have to update the file "rfzone/rel/files/sys.config" with your own settings.
You probably also have to update "rfzone/rel/reltool.config" with the correct path to your application (normally "{lib_dirs, ["../.."]}") and all apps you need.
```
       {app, sasl,   [{incl_cond, include}]},
       {app, stdlib, [{incl_cond, include}]},
       {app, kernel, [{incl_cond, include}]},
       {app, uart, [{incl_cond, include}]},
       {app, can, [{incl_cond, include}]},
       {app, canopen, [{incl_cond, include}]},
       {app, rfzone, [{incl_cond, include}]}
```


And then you run: 
```
$ rebar generate
```
.

When generating a new release the old has to be (re)moved.

Start node:

```sh
$ cd rel
$ rfzone/bin/rfzone start
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

rfzone is documented using edoc. To generate the documentation do:

```sh
$ cd rfzone
$ rebar doc
```
The result is a collection of html-documents under ```rfzone/doc```.
