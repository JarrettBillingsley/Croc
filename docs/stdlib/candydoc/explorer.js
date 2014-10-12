/* This file is a part of CanDyDOC fileset.
   File is written by Victor Nakoryakov and placed into the public domain.

   This file is javascript with classes that represents explorer window.
   And things related to navigation. */

var explorer = new Explorer();

///////////////////////////////////////////////////////////////////////////////
// Current symbol marker class constructor
///////////////////////////////////////////////////////////////////////////////
function Marker()
{
	this.top    = document.createElement("div");
	this.middle = document.createElement("div");
	this.bottom = document.createElement("div");
	this.container = document.createElement("div");

	this.setTo = function(term)
	{
		// find definition related to `term`
		var def = term.nextSibling;
		while (def && def.nodeName != "DD")
			def = def.nextSibling;

		var defHeight = 0;
		var childrenHeight = 0; // children of current declaration
		if (def)
		{
			defHeight = def.offsetHeight;
			var child = def.firstChild;

			// traverse until DL tag, until children definition
			while (child && child.nodeName != "DL")
				child = child.nextSibling;

			if (child)
				childrenHeight = child.offsetHeight;
		}

		this.top.style.height = term.offsetHeight;
		this.middle.style.height = defHeight - childrenHeight;
		this.bottom.style.height = childrenHeight;

		if (childrenHeight == 0)
			this.bottom.style.display = "none";
		else
			this.bottom.style.display = "";

		this.container.style.left = getLeft(term) - 8;
		this.container.style.top = getTop(term);
		this.container.style.display = "";
	}

	///////////////////////////////////////////////////////////////////////////
	this.container.style.position = "absolute";
	this.container.style.display = "none";

	this.top.className = "markertop";
	this.middle.className = "markermiddle";
	this.bottom.className = "markerbottom";

	this.container.appendChild(this.top);
	this.container.appendChild(this.middle);
	this.container.appendChild(this.bottom);

	//document.body.appendChild( this.container );

	// Workaround bug in IE 5/6. We can not append anything to document body until
	// full page load.
	window.marker = this;
	if (window.addEventListener)
		window.addEventListener("load", new Function("document.body.appendChild( window.marker.container );"), false);
	else if (window.attachEvent)
		window.attachEvent("onload", new Function("document.body.appendChild( window.marker.container );"));
}

///////////////////////////////////////////////////////////////////////////////
// Outline class constructor
///////////////////////////////////////////////////////////////////////////////
function Outline()
{
	this.tree           = new TreeView();
	this.mountPoint     = null;
	this.writeEnabled   = false;
	this.marker         = new Marker();
	this.classRegExp    = new RegExp;
	this.namespaceRegExp= new RegExp;
	this.fieldRegExp    = new RegExp;
	this.funcRegExp     = new RegExp;

	this.incSymbolLevel = function()
	{
		if (this.mountPoint == null)
			this.mountPoint = this.tree.children[ 0 ];
		else
			this.mountPoint = this.mountPoint.lastChild();
	}

	this.decSymbolLevel = function()
	{
		// place icons near items according to extracted below type
		for (var i = 0; i < this.mountPoint.children.length; ++i)
		{
			child = this.mountPoint.children[i];
			var term = child.termRef;

			// find first span node
			var n = term.firstChild;
			while (n && n.nodeName != "SPAN")
				n = n.nextSibling;

			if (!n) // shouldn't happen
				continue;

			var iconSrc;
			var text = n.firstChild.nextSibling.data;

			if ( this.classRegExp.test(text) )
				iconSrc = "candydoc/img/outline/class.gif";
			else if ( this.namespaceRegExp.test(text) )
				iconSrc = "candydoc/img/outline/namespace.png";
			else if(this.funcRegExp.test(text) && !this.fieldRegExp.test(text))
				iconSrc = "candydoc/img/outline/func.gif";
			else
				iconSrc = "candydoc/img/outline/var.gif";

			child.icon.src = iconSrc;
			child.icon.width = 16;
			child.icon.height = 16;
		}

		this.mountPoint = this.mountPoint.parentNode;
	}

	this.addDecl = function(decl)
	{
		function getLastLeaf(elem)
		{
			if (elem.childNodes.length > 0)
				return getLastLeaf(elem.lastChild);
			else
				return elem;
		}

		function getCurrentTerm()
		{
			var ret = getLastLeaf( document.getElementById("content") );
			while (ret && ret.nodeName != "DT")
				ret = ret.parentNode;

			return ret;
		}

		function afterDot(name)
		{
			var bits = name.split("\.");
			return bits[bits.length - 1];
		}

		if (this.writeEnabled)
		{
			var node = this.mountPoint.createChild(afterDot(decl));
			node.termRef = getCurrentTerm();
			node.anchor = document.getElementById(decl);

			if(!node.anchor)
				alert("NOOO " + decl);

			node.anchor.node_ = node;
			node.setOnclick( new Function("location.hash = '#' + this.anchor.id;") );
		}
	}

	this.mark = function(term)
	{
		this.marker.setTo(term);
		window.scrollTo(0, getTop(term) - getWindowHeight() / 6);
	}


	this.classRegExp.compile("^class(\b.*)?");
	this.namespaceRegExp.compile("^namespace(\b.*)?");
	this.fieldRegExp.compile(/^((\w+)\.)*(\w+)\s?=/);
	this.funcRegExp.compile(/.*\(.*/);
}




///////////////////////////////////////////////////////////////////////////////
// Package explorer class constructor
///////////////////////////////////////////////////////////////////////////////
function PackageExplorer()
{
	this.tree = new TreeView(true);

	this.addModule2 = function(mod, full)
	{
		var moduleIco = "candydoc/img/outline/module.gif";
		var packageIco = "candydoc/img/outline/package.gif";

		var path = mod.split("\.");
		var node = this.tree.branch(path[0]);
		if ( !node )
			node = this.tree.createBranch(path[0], (path.length == 1) ? moduleIco : packageIco);

		if(path.length == 1)
			node.setRef(mod + ".html");
		else
		{
			for (var i = 1; i < path.length; ++i)
			{
				var prev = node;
				node = node.child(path[i]);
				if (!node)
					node = prev.createChild(path[i], (path.length == i + 1) ? moduleIco : packageIco);

				if (path.length == i + 1) {
					if (full)
						node.setRef(mod + ".html");
					else
						node.setRef(path[i] + ".html");
				}
			}
		}
	}

	this.addModuleFull = function(mod)
	{
		this.addModule2(mod, true);
	}

	this.addModule = function(mod)
	{
		this.addModule2(mod, false);
	}
}



///////////////////////////////////////////////////////////////////////////////
// Explorer class constructor
///////////////////////////////////////////////////////////////////////////////
function Explorer()
{
	this.outline         = new Outline();
	this.packageExplorer = new PackageExplorer();
	this.tabs            = new Array();
	this.tabCount        = 0;

	this.initialize = function(moduleName)
	{
		this.tabArea = document.getElementById("tabarea");
		this.clientArea = document.getElementById("explorerclient");

		// prevent text selection
		this.tabArea.onmousedown = new Function("return false;");
		this.tabArea.onclick = new Function("return true;");
		this.tabArea.onselectstart = new Function("return false;");
		this.clientArea.onmousedown = new Function("return false;");
		this.clientArea.onclick = new Function("return true;");
		this.clientArea.onselectstart = new Function("return false;");

		this.outline.tree.createBranch( moduleName, "candydoc/img/outline/module.gif" );

		// create tabs
		this.createTab("Outline", this.outline.tree.domEntry);
		this.createTab("All Modules", this.packageExplorer.tree.domEntry);
	}

	this.createTab = function(name, domEntry)
	{
		var tab = new Object();
		this.tabs[name] = tab;
		this.tabCount++;

		tab.domEntry = domEntry;
		tab.labelSpan = document.createElement("span");

		if (this.tabCount > 1)
		{
			tab.labelSpan.className = "inactivetab";
			tab.domEntry.style.display = "none";
		}
		else
		{
			tab.labelSpan.className = "activetab";
			tab.domEntry.style.display = "";
		}

		tab.labelSpan.appendChild( document.createTextNode(name) );
		tab.labelSpan.owner = this;
		tab.labelSpan.onclick = new Function("this.owner.setSelection('" + name + "');");

		this.tabArea.appendChild( tab.labelSpan );
		this.clientArea.appendChild( domEntry );
	}

	this.setSelection = function(tabName)
	{
		for (name in this.tabs)
		{
			this.tabs[name].labelSpan.className = "inactivetab";
			this.tabs[name].domEntry.style.display = "none";
		}

		this.tabs[tabName].labelSpan.className = "activetab";
		this.tabs[tabName].domEntry.style.display = "";
	}
}

function changeHash()
{
	var hash = location.hash;

	if(hash.length)
	{
		var node = document.getElementById(location.hash.substring(1));

		node.node_.select();

		while(node && node.nodeName != "DT")
			node = node.parentNode;

		explorer.outline.mark(node);
	}
}

window.onload = changeHash;
window.onhashchange = changeHash;