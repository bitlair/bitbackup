# Files
## backup-hardlink-rsync.sh
Copies files to a local or remote endpoint, possibly via SSH.
Uses hardlinks for rotation (cp -al daily.0 daily.1) and rsync will create a new file with the delta and remove the old file to put the new file in place.
Because there is still a reference to the old file in daily.0 it is not removed from disk until it is removed out of the last remaining backup.

### Advantages
- Can use SSH as transport mechanism
- Easy to understand and recover (simply copy)
- Good for documents
- Encrypted file transfer

### Disadvantages
- No encrypted storage
- Can not backup to cloud services due to lack of encryption in storage
- Large files that change slightly use up a lot of space, like database dumps


## backup-encrypted-duplicity.sh
This uses duplicity with a public and private key. The private key is used for signing the backups, the public key is used to encrypt the backups.

### Advantages
- Uses SSH as transport
- Strong crypto for storage
- System cannot read the backup itself, only add to it.
- Can use cloud type storage, because of strong encryption
- Stores delta from previous backup, even for database dumps

### Disadvantages
- Harder to recover
- Maintains potentially large local cache of the previous backup for delta calculation
- More complex.
