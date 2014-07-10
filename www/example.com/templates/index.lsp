<!doctype html>
<html>
<head>
	<title>It works!</title>
	<meta charset="UTF-8">
	<link rel="stylesheet" href="//maxcdn.bootstrapcdn.com/bootstrap/3.2.0/css/bootstrap.min.css">
	<link rel="stylesheet" href="//maxcdn.bootstrapcdn.com/bootstrap/3.2.0/css/bootstrap-theme.min.css">
	<script src="//code.jquery.com/jquery-1.11.1.min.js"></script>
	<script src="//maxcdn.bootstrapcdn.com/bootstrap/3.2.0/js/bootstrap.min.js"></script>
</head>
<body role="document">
	<? printTemplate("templates/header.lsp") ?>
	
	<div class="container theme-showcase" role="main">
		<div class="jumbotron">
			<h1><? echo(welcomeMessage.title) ?></h1>
			<p><? echo(welcomeMessage.subtitle) ?></p>
			<p><? echo(welcomeMessage.text) ?></p>
			
			<p><a href="https://github.com/zeitgeist87/LuaServer"
			class="btn btn-primary btn-lg" role="button">Learn more &raquo;</a></p>
		</div>
		
		<? printTemplate("templates/uploads.lsp") ?>
		
		<? printTemplate("templates/articles.lsp") ?>
	</div>

	<article>
		
	</article>
</body>
</html>
