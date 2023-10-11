# Design of "TestOS"

## File and Directory handling

Files and directories will be stored in the mod storage of the mod. Directories
will just be a file containing references to other files.

## Boot-up script

a startup.lua file will be run in boot, users can put whatever script they like
in it.

## Basic Shell Utilities

### CD

Change Directory

### LS

List Files

### EDIT

Allows you to edit/create a file.

- Edit the file
- Save the file
- Close the file (Without saving)

### RM

Allows you to delete a file or directory

- use -R for recursive remove.

### Wget

Fetch files from the internet (requires being enabled in the settings).

## CLI

We have a stdin, stdout and stderr.
