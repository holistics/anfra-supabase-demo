<!-- anfra:begin -->
## anfra

This is an anfra repo.

- Use the anfra skills for work in this repo. They know anfra's languages and commands, so you'll work more
  accurately and efficiently with them than from memory.
- Docs: anfra at https://anfra.ai/docs, AML and AQL at https://amql.org/docs.

Keeping the skills working:

- Once per session, before your first anfra command, run `anfra version --skills <version>`, with the version
  from the `anfra skills` line at the end of an anfra skill you've loaded, or `--skills unknown` if it has no such
  line. Follow the hints it prints. If anfra doesn't know `--skills`, it's out of date: ask the user to run
  `anfra update`.
- If the anfra skills aren't available to you, run `anfra agent setup --agent <your id>` and follow what it says,
  then ask the user to restart you. If that fails, install them as https://github.com/holistics/anfra-skills says
  for the agent you are.
<!-- anfra:end -->
