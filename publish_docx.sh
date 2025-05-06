mkdir -p output
cd docs/en
pandoc -i em002-2.md -o ../../output/em002-2.docx \
          --verbose \
          --from=markdown+pipe_tables \
          --to=docx \
          --reference-doc=../../template/bk_template.docx