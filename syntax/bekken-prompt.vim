if exists("b:current_syntax")
  finish
endif

syntax match BekkenPromptCharacter /\v(^.{2})/ oneline
syntax match BekkenPromptCount /\v([0-9]{1,} \/ [0-9]{1,}$)/ oneline

highlight def link BekkenPromptCharacter Directory
highlight def link BekkenPromptCount Comment

let b:current_syntax = "bekken-prompt"
