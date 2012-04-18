Install tellstick as service 
============================

On a mac
========

Copy the file se.seazone.tellstick.plist.src into
se.seazone.tellstick.plist and then edit the variables
to be sane for you configuration. The file assumes that
the libraries are downloaded and compiled under the directory
%USER%/erlang.

   %USER%
   
This is replace with the short user name on the system, note
that this user must be allowed to open the tellstick device.

Now use launctl to load and start the tellstick server.

    launchctl load -w se.seazone.tellstick.plist
    
To stop the following command is used

    launchctl unload -w se.seazone.tellstick.plist
