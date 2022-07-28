output "module_paths" {
  value = {
    cwd    = path.cwd    # abspath git root
    module = path.module # "modules/config"
    root   = path.root   # "."
  }
}
