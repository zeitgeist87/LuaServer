<!-- Fixed navbar -->
<div class="navbar navbar-inverse navbar-fixed-top" role="navigation">
	<div class="container">
		<div class="navbar-header">
		<button type="button" class="navbar-toggle" data-toggle="collapse" data-target=".navbar-collapse">
			<span class="sr-only">Toggle navigation</span>
			<span class="icon-bar"></span>
			<span class="icon-bar"></span>
			<span class="icon-bar"></span>
		</button>
		<a class="navbar-brand" href="https://github.com/zeitgeist87/LuaServer">LuaServer</a>
		</div>
		<div class="navbar-collapse collapse">
		<ul class="nav navbar-nav">
			<li class="active"><a href="#">Home</a></li>
			<li><a href="#about">About</a></li>
			<li><a href="#contact">Contact</a></li>
			<li class="dropdown">
			<a href="#" class="dropdown-toggle" data-toggle="dropdown">Dependencies<span class="caret"></span></a>
			<ul class="dropdown-menu" role="menu">
			<? for _, dep in ipairs(dependencies) do ?>
				<li><a href="<? echo(dep.url) ?>"><? echo(dep.name) ?></a></li>
			<? end ?>
			</ul>
			</li>
		</ul>
		</div>
	</div>
</div>
