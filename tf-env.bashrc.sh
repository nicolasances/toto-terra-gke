# ---------------------------------------------------------------
# Append this to ~/.bashrc on the Terraform VM:
#
#   cat tf-env.bashrc.sh >> ~/.bashrc
#
# It loads the Terraform variables at login, but refuses to do so if the
# file is not owned by you or can be read by anyone else.
# ---------------------------------------------------------------
tf_env_file="$HOME/.config/toto-terra-gke/tf-env.sh"
if [ -f "$tf_env_file" ]; then
    if [ "$(stat -c '%U %a' "$tf_env_file")" = "$(id -un) 600" ]; then
        . "$tf_env_file"
    else
        echo "toto-terra-gke: NOT loading $tf_env_file, it must be owned by $(id -un) with mode 600 (chmod 600 $tf_env_file)" >&2
    fi
fi
unset tf_env_file
