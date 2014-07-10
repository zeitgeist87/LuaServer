<div class="page-header">
	<h1 id="Articles">Articles</h1>
</div>

<form method="post" action="#Articles">
	<fieldset>
		<label for="title">Title: </label><br />
		<input name="title" type="text" size="50" /> </br>
		<label for="text">Text: </label><br />
		<textarea name="text" rows="4" cols="50"> 
		</textarea><br />
		<input class="btn btn-primary" type="submit" value="Submit" />
	</fieldset>
</form>	

<br /><br />

<? for _, article in ipairs(articles) do ?>
<div class="panel panel-default">
	<div class="panel-heading">
		<h3 class="panel-title"><? echo(article.title) ?> - <? echo(os.date("!%a, %d %b %Y %X GMT", article.date)) ?></h3>
	</div>
	<div class="panel-body">
		<? echo(article.text) ?>
	</div>
</div>
<? end ?>