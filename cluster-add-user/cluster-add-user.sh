#!/usr/bin/zsh -e

while true; do
	case $1 in
		--help)
# Do not use tab for alignment because tab width varies!
			echo "
sudo $0 username

Options
--email         [Required] Specify the email of the new user.
--public-key    [Required] Specify public key of the new user.
--zsh           Use Z Shell.
"
			exit;;
		--email)
			email=$2; shift 2;;
		--public-key)
			publicKey=$2; shift 2;;
		*)
			break;;
	esac
done

username=$argv[-1]
[[ -z $email ]] && echo '--email is not specified.' >&2 && exit 1
[[ -z $publicKey ]] && echo '--public-key is not specified.' >&2 && exit 1


if (( $argv[(Ie)--zsh] )); then
	s='--shell /usr/bin/zsh'
else
	s=''
fi

# The first % in parenthis is Parameter Expansion Flag, asking to expand like in prompt
# %N is a prompt expension variable.
# https://stackoverflow.com/a/23259585/746461
pushd $(dirname ${(%):-%N})
sudo adduser --conf adduser.conf --gecos ",,,,$email" --disabled-password $=s  $username

uid=$(id -u $username)
gid=$(id -g $username)

mv /home/$username /home/$username-tmp

btrfs subvolume create /home/$username
btrfs subvolume create /home/shared/$username
chown $username: /home/$username
chown $username: /home/shared/$username

# (D) sets the GLOB_DOTS option for the current pattern
mv /home/$username-tmp/*(D) /home/$username
rm -rf /home/$username-tmp

ln -s /home/shared/$username /home/$username/shared

# When user runs `srun` on aha, the user's groups are captured
# on aha, then transfered to eureka. 
# Although we put the user to group aptuser, the sudoers file doesn't
# have corresponding rules so the user cannot run `sudo apt` on aha.
# Eureka has the corresponding sudoers rule.
usermod -aG aptuser,conda-cache $username

sudo -u $username cp -r ../slurm-examples /home/$username/shared/



gecos=$(getent passwd $username | cut -d ':' -f 5)

remoteFile=/home/qiqig/shared/remote-add-user
cat <<HERE > $remoteFile
#!/bin/bash -e
sudo addgroup --gid $gid $username
# It's not documented clearly, but --gid requires the existence of GID.
sudo adduser --gecos ",,,,$email" --disabled-login --uid $uid --gid $gid $username
sudo usermod -aG conda-cache $username

sudo ln -s /home/shared/$username /home/$username/shared
HERE

chmod +x $remoteFile

IFS=', ' read -A computeNodes <<< "$(sinfo --format %N --noheader)"

for server in "$computeNodes[@]"
do
	echo $server
	if ! sudo -u qiqig ssh $server $remoteFile; then
		echo "Failed to execute remote command, please run ~/shared/remote-add-user on $server."
	fi
done

mkdir -p /home/$username/.ssh
echo $publicKey > /home/$username/.ssh/authorized_keys
chmod 700 /home/$username/.ssh
chmod 600 /home/$username/.ssh/authorized_keys
chown -R $username:$username /home/$username/.ssh

emailBody="Account: $username
Public Key: $publicKey"
sendemail -f aha@ipm.edu.mo -t $email -s mail.ipm.edu.mo -u 'Shine Cluster Account Created' -m "$emailBody"
