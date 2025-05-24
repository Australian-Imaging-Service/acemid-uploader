# ACEMID_UPLOADER

This code repo contains several bash scripts for uploading ACEMID data to your XNAT.

Before running the bash scripts, please make sure that you have turned on the External Camera Session (xnat:xcSessionData) and External Camera Scan (xnat:xcScanData) data types.

(1) ACEMID_uploader.sh The main ACEMID bash script to upload the cleaned vectra exported data files to your XNAT instance using JSESSIONID.

(2) dermoscopy_data_upload.sh The bash script to upload the dermoscopy images (mainly in jpg or png) to your XNAT instance.

(3) stage_server_monitor.sh The bash script to monitor the exported data from Vectra system to your specified network drive to detect if there is any file or folder changes in real time and it will trigger the upload script.

(4) remove_phi_report.sh The bash script used to remove the PHI info in pdf reports.

(5) Dockerfile The Dockerfile used to build the docker image of the above bash scripts to run on different platforms.
