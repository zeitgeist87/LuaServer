<div class="page-header">
	<h1 id="Uploads">Uploads</h1>
</div>

<form method="post" action="#Uploads" enctype="multipart/form-data">
	<fieldset>
		<label for="file1">Upload Files: </label>
		<input name="file1" id="file1" type="file" size="30" />
		<input name="file2" id="file2" type="file" size="30" /> <br />
		
		<input class="btn btn-primary" type="submit" value="Upload" />
	</fieldset>
</form>	

<?
if files then
	echo("<h3>Files sucessfully uploaded!</h3>")
	for _, file in pairs(files) do ?>
		<p>
		<a href="/uploads/<? echo(file.name) ?>">
		<? echo(file.name) ?>
		</a> (<? echo(file.size) ?> bytes)
		</p>
	<?
	end
end
?>