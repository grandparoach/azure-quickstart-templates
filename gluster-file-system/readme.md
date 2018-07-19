<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fgrandparoach%2Fazure-quickstart-templates%2Fgluster%2Fgluster-file-system%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

This template lets you create an N node Gluster File System on CentOS 7.4. You can provision 2, 4, 6 or 8 nodes in a cluster with a replication factor of 2. These machines will be placed into the same Availability Set.  There are no public IP addresses, so it must be installed onto an existing Virtual Network.  The number and size of the attached disks are specified as input parameters.  The attached disks will be striped into a RAID0 file system.  NFS is disabled, so all the clients must use the gluster native fuse client to access the file system.

The settings for these servers have been adopted from the guidance mentioned in this eBook  https://azure.microsoft.com/mediahandler/files/resourcefiles/parallel-virtual-file-systems-on-microsoft-azure/Parallel_Virtual_File_Systems_on_Microsoft_Azure.pdf 
