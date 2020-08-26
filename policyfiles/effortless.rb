name 'effortless'

# Where to find external cookbooks:
default_source :supermarket

# run_list: chef-client will run these recipes in the order specified.
run_list 'jb_client'

cookbook 'jb_client', path: '../cookbooks/jb_client'
