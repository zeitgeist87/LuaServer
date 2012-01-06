<? 
--has to come first so that set-cookie header can be sent
local s=req:getSession() 

?>
<html>
<? include("templates/head.lua") ?>
<body>
<h1><? 
	local c=db.get("count")
	if not c then
		c=0
	end

	c=c+1

	--length of the output must not change,
	--because this is reported as an error in benchmark tools
	if c>9 then
		c=0
	end
	send("It works! Number: ", c) 

	db.put("count",c)

	--make change to db persistent
	--db.sync()
?></h1>

<h2>
<?
	local c=s.c
	if not c then
		c=0
	end

	c=c+1
	
	--length of the output must not change,
	--because this is reported as an error in benchmark tools
	if c>9 then
		c=0
	end
	send("It works! Number: ", c) 

	s.c=c

?>
</h2>


<?
	--open http://localhost:8080/?xss=It%20works
	local xss=req.get.xss
	if xss then
		send("<h3>", xss,"</h3>") 
	end
?>

</body>
</html>
