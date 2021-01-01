LDL + ChirpStack Virtual Integration Test
=========================================

This is a Ruby program that:

- runs instances of the LDL Ruby wrapper
- orchestrates ChirpStack via Docker Compose
- implements a ChirpStack application and join server
- runs minitest spec tests

## Running

You will need to have Ruby and docker-compose installed.

```
bundle install
bundle exec ruby app.rb
```

The terminal output is very noisy but minitest will make it clear
at the end if any tests have failed.

Run-time may be up to one day depending on which tests are included.
At the moment I am simply commenting in/out the tests I want to run in
the top level script.

## See Also

- [LDL](https://github.com/cjhdev/lora_device_lib)
- [ChirpStack](https://www.chirpstack.io/)
