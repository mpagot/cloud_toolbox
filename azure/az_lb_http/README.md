Create a deployment with 3 VM running a nginx service. They are presenting 3 different static web pages on port 80. They are grouped in an `Availability set` (not a `Scale set`). A load balancer is in front of them. The load balancer has the only public IP in the deployment.

The main script to run is `azure_lb_web.sh`. It expects you have a working and authenticated `az cli` installation.

There are few variables on the top of the script that allow some configurations (like the name of all the deployed resources).

The `cloud-init-web.txt` file is a `cloud-init` configuration file injected at each VM creation. It is mostly in charge to install and set up the nginx service.

At the end of the deployment you will get a URL. Open it in the browser and eventually reload the page multiple time to see the load balancer to redirect you on one of the 3 VM.

This demo is inspired by https://youtu.be/T7XU6Lz8lJw?si=jRG_K2xI9YzVjGz2 and https://github.com/MarczakIO/azure4everyone-samples/blob/master/azure-load-balancer-introduction/environment-create.sh
